import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { generateObject } from "ai";
import { openai } from "../core/config";
import { z } from "zod";

import { requireAuth } from "../core/auth";

const firestore = admin.firestore();
import { COLLECTION_CONVERSATIONS, SUBCOLLECTION_MESSAGES } from "../core/constants";

// ============================================================================ 
// Priority Classification Trigger
// ============================================================================ 

// Zod schema for priority classification response
const priorityClassificationSchema = z.object({
  score: z.number().min(1).max(5).describe("Priority score from 1 (low) to 5 (urgent)"),
  label: z.enum(["low", "medium", "high", "urgent", "critical"]).describe("Priority label"),
  rationale: z.string().describe("Brief explanation of the priority assessment"),
});

type PriorityClassification = z.infer<typeof priorityClassificationSchema>;

// Default priority for messages without classification
const DEFAULT_PRIORITY: PriorityClassification = {
  score: 2,
  label: "medium",
  rationale: "Default priority - message not yet analyzed",
};

/**
 * Gets priority metadata with safe defaults for missing fields
 */
function getPriorityWithDefaults(
  messageData: FirebaseFirestore.DocumentData
): PriorityClassification & { analyzedAt: admin.firestore.Timestamp | null } {
  return {
    score: messageData.priorityScore ?? DEFAULT_PRIORITY.score,
    label: messageData.priorityLabel ?? DEFAULT_PRIORITY.label,
    rationale: messageData.priorityRationale ?? DEFAULT_PRIORITY.rationale,
    analyzedAt: messageData.priorityAnalyzedAt ?? null,
  };
}

/**
 * Validates and normalizes priority data
 */
function normalizePriorityData(data: Partial<PriorityClassification>): PriorityClassification {
  // Validate score is in range
  const score = Math.max(1, Math.min(5, data.score ?? DEFAULT_PRIORITY.score));

  // Validate label is one of the allowed values
  const validLabels: Array<PriorityClassification["label"]> = ["low", "medium", "high", "urgent", "critical"];
  const label = validLabels.includes(data.label as any) ? data.label! : DEFAULT_PRIORITY.label;

  return {
    score,
    label,
    rationale: data.rationale ?? DEFAULT_PRIORITY.rationale,
  };
}

/**
 * Classifies the priority of a message using OpenAI
 */
async function classifyMessagePriority(messageText: string): Promise<PriorityClassification> {
  const systemPrompt = `You are a message priority classifier. Analyze the given message and determine its priority level based on:
- Urgency indicators (words like "urgent", "ASAP", "immediately")
- Time sensitivity (deadlines, time-bound requests)
- Impact and importance (critical issues, blockers)
- Tone and emphasis (exclamation marks, capitalization)
- Context clues (questions vs statements, requests vs updates)

Priority levels:
- 1 (low): General updates, casual conversation, no urgency
- 2 (medium): Standard questions or requests, no deadline
- 3 (high): Important matters with some urgency or upcoming deadlines
- 4 (urgent): Time-sensitive requests, issues requiring quick attention
- 5 (critical): Emergency situations, critical blockers, immediate action needed

Provide a brief rationale for your assessment.`;

  const userPrompt = `Classify the priority of this message:\n\n${messageText}`;

  try {
    const { object: classification } = await generateObject({
      model: openai("gpt-4o-mini"),
      system: systemPrompt,
      prompt: userPrompt,
      schema: priorityClassificationSchema,
      temperature: 0.2,
    });

    return classification;
  } catch (error) {
    console.error("[classifyMessagePriority] Error:", error);
    return DEFAULT_PRIORITY;
  }
}

/**
 * Checks if a message should be classified for priority
 */
function shouldClassifyPriority(messageData: FirebaseFirestore.DocumentData): boolean {
  const senderId = messageData.senderId as string | undefined;
  const text = messageData.text as string | undefined;

  // Skip if no sender or text
  if (!senderId || !text) {
    return false;
  }

  // Skip bot messages (format: "bot:botId")
  if (senderId.startsWith("bot:")) {
    return false;
  }

  // Skip system messages
  if (messageData.isSystemMessage === true) {
    return false;
  }

  // Skip if already analyzed
  if (messageData.priorityAnalyzedAt) {
    return false;
  }

  return true;
}

/**
 * Firebase trigger: Analyzes priority of new messages
 * Runs when a new message is created in any conversation
 */
export const analyzeMessagePriority = onDocumentCreated(
  "conversations/{conversationId}/messages/{messageId}",
  async (event) => {
    const messageData = event.data?.data();

    if (!messageData) {
      console.log("[analyzeMessagePriority] No message data found");
      return;
    }

    // Check if this message should be classified
    if (!shouldClassifyPriority(messageData)) {
      console.log("[analyzeMessagePriority] Skipping classification - message doesn't meet criteria");
      return;
    }

    const messageText = messageData.text as string;
    const conversationId = event.params.conversationId;
    const messageId = event.params.messageId;

    console.log(`[analyzeMessagePriority] Analyzing message ${messageId} in conversation ${conversationId}`);

    try {
      // Classify the message priority
      const rawClassification = await classifyMessagePriority(messageText);

      // Normalize the classification to ensure valid data
      const classification = normalizePriorityData(rawClassification);

      console.log(`[analyzeMessagePriority] Classification result:`, {
        score: classification.score,
        label: classification.label,
        rationale: classification.rationale.substring(0, 100),
      });

      // Update the message document with priority metadata
      await event.data?.ref.set(
        {
          priorityScore: classification.score,
          priorityLabel: classification.label,
          priorityRationale: classification.rationale,
          priorityAnalyzedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      console.log(`[analyzeMessagePriority] Successfully updated message ${messageId} with priority data`);
    } catch (error) {
      console.error(`[analyzeMessagePriority] Error classifying message ${messageId}:`, error);
      // Don't throw - we don't want to block message creation if classification fails
    }
  }
);

/**
 * Backfill priority analysis for existing messages
 * Analyzes messages in a conversation that don't have priority data
 */
export const backfillMessagePriorities = onCall<{
  conversationId: string;
  limit?: number;
}>(async (request) => {
  const uid = requireAuth(request);
  const { conversationId, limit = 50 } = request.data;

  console.log(`[backfillMessagePriorities] Starting backfill for conversation ${conversationId}, limit: ${limit}`);

  try {
    // Verify user is a participant in the conversation
    const conversationDoc = await firestore
      .collection(COLLECTION_CONVERSATIONS)
      .doc(conversationId)
      .get();

    if (!conversationDoc.exists) {
      throw new HttpsError("not-found", "Conversation not found");
    }

    const conversationData = conversationDoc.data();
    const participantIds = conversationData?.participantIds as string[] || [];

    if (!participantIds.includes(uid)) {
      throw new HttpsError("permission-denied", "User is not a participant in this conversation");
    }

    // Query messages without priority analysis
    const messagesSnapshot = await firestore
      .collection(COLLECTION_CONVERSATIONS)
      .doc(conversationId)
      .collection(SUBCOLLECTION_MESSAGES)
      .where("priorityAnalyzedAt", "==", null)
      .orderBy("createdAt", "desc")
      .limit(limit)
      .get();

    console.log(`[backfillMessagePriorities] Found ${messagesSnapshot.docs.length} messages to analyze`);

    let analyzed = 0;
    let skipped = 0;
    let failed = 0;

    // Process messages in batches to avoid timeout
    const promises = messagesSnapshot.docs.map(async (doc) => {
      const messageData = doc.data();

      // Check if should classify
      if (!shouldClassifyPriority(messageData)) {
        skipped++;
        return;
      }

      try {
        const messageText = messageData.text as string;
        const rawClassification = await classifyMessagePriority(messageText);
        const classification = normalizePriorityData(rawClassification);

        await doc.ref.set(
          {
            priorityScore: classification.score,
            priorityLabel: classification.label,
            priorityRationale: classification.rationale,
            priorityAnalyzedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        analyzed++;
      } catch (error) {
        console.error(`[backfillMessagePriorities] Failed to analyze message ${doc.id}:`, error);
        failed++;
      }
    });

    await Promise.all(promises);

    console.log(`[backfillMessagePriorities] Complete - analyzed: ${analyzed}, skipped: ${skipped}, failed: ${failed}`);

    return {
      conversationId,
      analyzed,
      skipped,
      failed,
      total: messagesSnapshot.docs.length,
    };
  } catch (error) {
    console.error("[backfillMessagePriorities] Error:", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", "Failed to backfill message priorities", error);
  }
});

// ============================================================================ 
// AI Feature: Scheduling Intent Detection
// ============================================================================ 

// Zod schema for scheduling intent classification
const schedulingIntentSchema = z.object({
  hasSchedulingIntent: z.boolean().describe("Whether the message contains scheduling language"),
  confidence: z.number().min(0).max(1).describe("Confidence score 0-1"),
  reasoning: z.string().describe("Brief explanation of the classification"),
  suggestedKeywords: z.array(z.string()).optional().describe("Key scheduling-related phrases detected"),
});

type SchedulingIntentClassification = z.infer<typeof schedulingIntentSchema>;

/**
 * Default classification for messages without scheduling intent
 */
const DEFAULT_NO_INTENT: SchedulingIntentClassification = {
  hasSchedulingIntent: false,
  confidence: 0,
  reasoning: "No scheduling language detected",
  suggestedKeywords: [],
};

/**
 * Checks if a message should be classified for scheduling intent
 */
function shouldClassifySchedulingIntent(messageData: FirebaseFirestore.DocumentData): boolean {
  const senderId = messageData.senderId as string | undefined;
  const text = messageData.text as string | undefined;

  // Skip if no sender or text
  if (!senderId || !text) {
    return false;
  }

  // Skip bot messages (format: "bot:botId")
  if (senderId.startsWith("bot:")) {
    return false;
  }

  // Skip system messages
  if (messageData.isSystemMessage === true) {
    return false;
  }

  // Skip if already analyzed
  if (messageData.schedulingIntentAnalyzedAt) {
    return false;
  }

  return true;
}

/**
 * Classifies message for scheduling intent using OpenAI
 */
async function classifySchedulingIntent(messageText: string): Promise<SchedulingIntentClassification> {
  

  const systemPrompt = `You are a scheduling intent classifier. Analyze the given message and determine if it contains scheduling-related language or intent.

Scheduling Intent Indicators:
- Explicit scheduling requests: "let's meet", "schedule a call", "set up a meeting"
- Time-based questions: "when are you free?", "what time works?", "available next week?"
- Calendar references: "check my calendar", "book some time", "find a slot"
- Coordination language: "let's sync up", "need to discuss", "catch up soon"
- Deadline mentions: "by end of week", "before Friday", "need to talk today"

Consider:
- Direct scheduling requests (high confidence)
- Implied scheduling needs (medium confidence)
- Time-related questions without scheduling context (low confidence)
- Casual mentions of time without coordination intent (no intent)

Return:
- hasSchedulingIntent: true if message shows scheduling coordination intent
- confidence: 0-1 score (0.7+ for strong intent, 0.4-0.7 for possible intent, <0.4 for unlikely)
- reasoning: Brief explanation
- suggestedKeywords: Key phrases that indicate scheduling`;

  const userPrompt = `Classify this message for scheduling intent:

"${messageText}"`;

  try {
    const { object: classification } = await generateObject({
      model: openai("gpt-4o-mini"),
      system: systemPrompt,
      prompt: userPrompt,
      schema: schedulingIntentSchema,
      temperature: 0.2, // Low temperature for consistent classification
    });

    return classification;
  } catch (error) {
    console.error("[classifySchedulingIntent] Error:", error);
    return DEFAULT_NO_INTENT;
  }
}

/**
 * Firebase trigger: Detects scheduling intent in new messages
 * Runs when a new message is created in any conversation
 */
export const detectSchedulingIntent = onDocumentCreated(
  "conversations/{conversationId}/messages/{messageId}",
  async (event) => {
    const messageData = event.data?.data();

    if (!messageData) {
      console.log("[detectSchedulingIntent] No message data found");
      return;
    }

    // Check if this message should be classified
    if (!shouldClassifySchedulingIntent(messageData)) {
      console.log("[detectSchedulingIntent] Skipping classification - message doesn't meet criteria");
      return;
    }

    const messageText = messageData.text as string;
    const conversationId = event.params.conversationId;
    const messageId = event.params.messageId;

    console.log(`[detectSchedulingIntent] Analyzing message ${messageId} in conversation ${conversationId}`);

    try {
      // Classify the message for scheduling intent
      const classification = await classifySchedulingIntent(messageText);

      console.log(`[detectSchedulingIntent] Classification result:`, {
        hasIntent: classification.hasSchedulingIntent,
        confidence: classification.confidence,
        reasoning: classification.reasoning.substring(0, 100),
      });

      // Only write if there's meaningful intent (confidence >= 0.4)
      if (classification.confidence >= 0.4) {
        await event.data?.ref.set(
          {
            schedulingIntent: classification.hasSchedulingIntent,
            schedulingIntentConfidence: classification.confidence,
            schedulingIntentReasoning: classification.reasoning,
            schedulingIntentKeywords: classification.suggestedKeywords || [],
            schedulingIntentAnalyzedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        console.log(`[detectSchedulingIntent] Updated message ${messageId} with scheduling intent data`);
      } else {
        // Still mark as analyzed to prevent re-processing
        await event.data?.ref.set(
          {
            schedulingIntent: false,
            schedulingIntentConfidence: classification.confidence,
            schedulingIntentAnalyzedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        console.log(`[detectSchedulingIntent] Low confidence (${classification.confidence}), marked as no intent`);
      }
    } catch (error) {
      console.error(`[detectSchedulingIntent] Error classifying message ${messageId}:`, error);
      // Don't throw - we don't want to block message creation if classification fails
    }
  }
);