import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { generateObject } from "ai";
import { openai } from "../core/config";
import { z } from "zod";
import { requireAuth } from "../core/auth";
import { fetchSenderNames } from "../core/utils";
import crypto from "crypto";

const firestore = admin.firestore();
import { COLLECTION_CONVERSATIONS, COLLECTION_USERS, COLLECTION_BOTS } from "../core/constants";


// ============================================================================ 
// AI Feature: Action Item Extraction
// ============================================================================ 

interface ExtractActionItemsRequest {
  conversationId: string;
  windowDays?: number; // Default: 7 days
}

// Define the action item schema using Zod for validation
const actionItemSchema = z.object({
  id: z.string().describe("Unique identifier for the action item"),
  task: z.string().describe("Description of the action item or task"),
  assignedTo: z.string().optional().describe("User ID or email of the person assigned"),
  dueDate: z.string().optional().describe("ISO 8601 date string for when the task is due"),
  priority: z.enum(["low", "medium", "high", "urgent"]).describe("Priority level of the task"),
  status: z.enum(["pending", "in_progress", "completed", "cancelled"]).describe("Current status of the task"),
});

const actionItemsResponseSchema = z.object({
  actionItems: z.array(actionItemSchema).describe("List of extracted action items"),
});

/**
 * Generate a deterministic ID for an action item based on its content
 * This prevents duplicates when re-extracting the same action items
 */
function generateActionItemId(
  conversationId: string,
  task: string,
  assignedTo?: string
): string {
  const normalizedTask = task.toLowerCase().trim();
  const normalizedAssignee = assignedTo?.toLowerCase().trim() || "unassigned";
  const content = `${conversationId}:${normalizedTask}:${normalizedAssignee}`;
  const hash = crypto.createHash("sha256").update(content).digest("hex");
  return `action-${hash.substring(0, 16)}`;
}

/**
 * Callable function to extract action items from recent conversation messages
 * Uses OpenAI to analyze messages and identify actionable tasks with metadata
 */
export const extractActionItems = onCall<ExtractActionItemsRequest>(async (request) => {
  const uid = requireAuth(request);
  const { conversationId, windowDays = 7 } = request.data;

  try {
    console.log(`[extractActionItems] Starting extraction for conversation ${conversationId}, windowDays: ${windowDays}`);

    // Verify user is a participant in the conversation
    const conversationRef = firestore.collection(COLLECTION_CONVERSATIONS).doc(conversationId);
    console.log(`[extractActionItems] Fetching conversation document...`);
    const conversationDoc = await conversationRef.get();

    if (!conversationDoc.exists) {
      throw new HttpsError("not-found", `Conversation ${conversationId} not found`);
    }

    const conversationData = conversationDoc.data();
    const participantIds = conversationData?.participantIds || [];

    if (!participantIds.includes(uid)) {
      throw new HttpsError(
        "permission-denied",
        "User is not a participant in this conversation"
      );
    }

    console.log(`[extractActionItems] User ${uid} is authorized participant`);

    // Calculate the cutoff date for the time window
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - windowDays);

    console.log(`[extractActionItems] Fetching messages since ${cutoffDate.toISOString()}...`);

    // Fetch messages from the last N days
    let messagesSnapshot;
    try {
      messagesSnapshot = await conversationRef
        .collection("messages")
        .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(cutoffDate))
        .orderBy("timestamp", "asc")
        .limit(100) // Limit to prevent excessive token usage
        .get();
    } catch (queryError) {
      console.error(`[extractActionItems] Firestore query failed:`, queryError);
      throw new HttpsError(
        "internal",
        `Failed to query messages: ${queryError instanceof Error ? queryError.message : String(queryError)}`,
        queryError
      );
    }

    if (messagesSnapshot.empty) {
      console.log(`[extractActionItems] No messages found in ${windowDays}-day window for conversation ${conversationId}`);
      return {
        action_items: [],
        conversation_id: conversationId,
        window_days: windowDays,
        message_count: 0,
      };
    }

    console.log(`[extractActionItems] Found ${messagesSnapshot.docs.length} messages in ${windowDays}-day window`);

    // Build message context with participant names
    const messages = messagesSnapshot.docs.map((doc) => doc.data());

    // Fetch participant display names for context
    const senderIds = [...new Set(messages.map((msg) => msg.senderId))];
    const displayNames: Record<string, string> = {};

    for (const senderId of senderIds) {
      if (senderId.startsWith("bot:")) {
        const botId = senderId.substring(4);
        const botDoc = await firestore.collection(COLLECTION_BOTS).doc(botId).get();
        if (botDoc.exists) {
          displayNames[senderId] = botDoc.data()?.name || "AI Assistant";
        }
      } else {
        const userDoc = await firestore.collection(COLLECTION_USERS).doc(senderId).get();
        if (userDoc.exists) {
          displayNames[senderId] = userDoc.data()?.displayName || "Unknown User";
        }
      }
    }

    // Build conversation context
    const conversationText = messages
      .map((msg) => {
        const senderName = displayNames[msg.senderId] || "Unknown";
        return `[${senderName}]: ${msg.text}`;
      })
      .join("\n");

    // System prompt for action item extraction
    const systemPrompt = `You are an AI assistant specialized in extracting action items and tasks from conversation messages.\n\nYour task is to analyze the conversation and identify:\n1. Explicit action items (tasks someone said they would do)\n2. Implied commitments or responsibilities\n3. Deadlines or time-sensitive items\n4. Assigned tasks (who is responsible)\n5. Priorities based on context\n\nFor each action item, determine:\n- A clear, concise description of the task\n- Who it's assigned to (if mentioned)\n- When it's due (if mentioned)\n- The priority level (low, medium, high, urgent)\n- Current status (pending by default, unless mentioned as in-progress or completed)\n\nGenerate a unique ID for each action item using a combination of timestamp and index.\nFormat due dates as ISO 8601 strings if dates are mentioned.\nIf an assignee is mentioned by name, try to match it to a participant in the conversation.\n\nOnly extract genuine action items - ignore casual mentions or hypothetical discussions.`;

    const userPrompt = `Analyze the following conversation and extract all action items:\n\n${conversationText}`;

    console.log(`[extractActionItems] Analyzing ${conversationText.split('\n').length} lines of conversation`);

    // Call OpenAI for action item extraction using Vercel AI SDK
    let extractedData;
    try {
      console.log(`[extractActionItems] Calling OpenAI API...`);
      const result = await generateObject({
        model: openai("gpt-4o-mini"),
        system: systemPrompt,
        prompt: userPrompt,
        schema: actionItemsResponseSchema,
        temperature: 0.2, // Lower temperature for more deterministic extraction
      });
      extractedData = result.object;
      console.log(`[extractActionItems] OpenAI found ${extractedData.actionItems.length} action items`);
    } catch (aiError) {
      console.error(`[extractActionItems] OpenAI API call failed:`, aiError);
      throw new HttpsError(
        "internal",
        `AI extraction failed: ${aiError instanceof Error ? aiError.message : String(aiError)}`,
        aiError
      );
    }

    // Format response and persist to Firestore
    // Use deterministic IDs based on content hash to prevent duplicates
    const actionItems = extractedData.actionItems.map((item) => ({
      id: generateActionItemId(conversationId, item.task, item.assignedTo),
      task: item.task,
      assigned_to: item.assignedTo || null,
      due_date: item.dueDate || null,
      priority: item.priority,
      status: item.status,
      conversation_id: conversationId,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }));

    // Persist action items to Firestore subcollection with proper Timestamps
    console.log(`[extractActionItems] Preparing to persist ${actionItems.length} action items to Firestore...`);
    const batch = firestore.batch();
    const actionItemsRef = conversationRef.collection("actionItems");

    try {
      for (const actionItem of actionItems) {
        const itemRef = actionItemsRef.doc(actionItem.id);
        const existingDoc = await itemRef.get();

        // Prepare Firestore data with Timestamps and camelCase field names for Swift
        const firestoreData = {
          task: actionItem.task,
          assignedTo: actionItem.assigned_to,
          dueDate: actionItem.due_date ? admin.firestore.Timestamp.fromDate(new Date(actionItem.due_date)) : null,
          priority: actionItem.priority,
          status: actionItem.status,
          conversationId: actionItem.conversation_id,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        if (existingDoc.exists) {
          // Update existing action item, preserving created_at
          batch.set(itemRef, firestoreData, { merge: true });
        } else {
          // Create new action item with createdAt
          batch.set(itemRef, {
            ...firestoreData,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }

      console.log(`[extractActionItems] Committing batch write...`);
      await batch.commit();
      console.log(`[extractActionItems] Persisted ${actionItems.length} action items to Firestore`);
    } catch (firestoreError) {
      console.error(`[extractActionItems] Firestore batch write failed:`, firestoreError);
      throw new HttpsError(
        "internal",
        `Failed to persist action items: ${firestoreError instanceof Error ? firestoreError.message : String(firestoreError)}`,
        firestoreError
      );
    }

    const response = {
      action_items: actionItems,
      conversation_id: conversationId,
      window_days: windowDays,
      message_count: messages.length,
    };

    console.log(`[extractActionItems] Returning response with ${response.action_items.length} items`);

    return response;
  } catch (error) {
    console.error("[extractActionItems] Error occurred:", error);
    console.error("[extractActionItems] Error stack:", error instanceof Error ? error.stack : "No stack trace");
    console.error("[extractActionItems] Error details:", JSON.stringify(error, null, 2));

    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError(
      "internal",
      `Failed to extract action items: ${error instanceof Error ? error.message : String(error)}`,
      error
    );
  }
});

// ============================================================================ 
// Decision Tracking
// ============================================================================ 

// Zod schema for decision extraction
const decisionSchema = z.object({
  decisionText: z.string().describe("The decision that was made"),
  contextSummary: z.string().describe("Brief context explaining why this decision was made"),
  participantIds: z.array(z.string()).describe("User IDs of people involved in the decision"),
  decidedAt: z.string().describe("ISO timestamp when the decision was made"),
  followUpStatus: z.enum(["pending", "completed", "cancelled"]).describe("Current status of any follow-up actions"),
  confidenceScore: z.number().min(0).max(1).describe("Confidence that this is actually a decision (0-1)"),
});

const decisionsResponseSchema = z.object({
  decisions: z.array(decisionSchema).describe("List of decisions found in the conversation"),
});

type Decision = z.infer<typeof decisionSchema>;
type DecisionsResponse = z.infer<typeof decisionsResponseSchema>;

/**
 * Records decisions from a conversation using OpenAI
 */
export const recordDecisions = onCall<{
  conversationId: string;
  windowDays?: number;
}>(async (request) => {
  const uid = requireAuth(request);
  const { conversationId, windowDays = 30 } = request.data;

  console.log(`[recordDecisions] Analyzing conversation ${conversationId} for decisions`);

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

    // Calculate time window
    const windowStart = new Date();
    windowStart.setDate(windowStart.getDate() - windowDays);

    // Fetch messages from the window
    const messagesSnapshot = await firestore
      .collection(COLLECTION_CONVERSATIONS)
      .doc(conversationId)
      .collection("messages")
      .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(windowStart))
      .orderBy("timestamp", "asc")
      .limit(200) // Limit to avoid token overflow
      .get();

    if (messagesSnapshot.empty) {
      console.log(`[recordDecisions] No messages in window for conversation ${conversationId}`);
      return { decisions: [] };
    }

    // Fetch sender names for context
    const senderIds = new Set<string>();
    const messageData: Array<{ 
      senderId: string;
      text: string;
      timestamp: Date;
    }> = [];

    messagesSnapshot.docs.forEach(doc => {
      const data = doc.data();
      const senderId = data.senderId as string;
      const text = data.text as string;
      const timestamp = (data.timestamp as admin.firestore.Timestamp)?.toDate() || new Date();

      senderIds.add(senderId);
      messageData.push({ senderId, text, timestamp });
    });

    // Fetch sender names
    const senderNames = await fetchSenderNames(Array.from(senderIds));

    // Build conversation transcript
    const transcript = messageData.map(msg => {
      const senderName = senderNames[msg.senderId] || "Unknown";
      const timeStr = msg.timestamp.toISOString();
      return `[${timeStr}] ${senderName}: ${msg.text}`;
    }).join("\n");

    // Extract decisions using OpenAI
    const systemPrompt = `You are a decision tracking assistant. Analyze the conversation transcript and identify any decisions that were made.\n\nA decision is:\n- A concrete choice or commitment made by participants\n- Something actionable or that changes plans/direction\n- Not just a suggestion or possibility, but a finalized choice\n\nFor each decision, provide:\n- The decision text (what was decided)\n- Context summary (why it was decided)\n- Participant IDs of those involved\n- Timestamp when it was decided\n- Follow-up status (pending by default)\n- Confidence score (how certain you are this is a real decision)\n\nOnly include decisions with confidence >= 0.7`;

    const userPrompt = `Analyze this conversation and extract decisions:\n\n${transcript}`;

    const { object: response } = await generateObject({
      model: openai("gpt-4o-mini"),
      system: systemPrompt,
      prompt: userPrompt,
      schema: decisionsResponseSchema,
      temperature: 0.2,
    });

    // Filter decisions by confidence
    const highConfidenceDecisions = response.decisions.filter(d => d.confidenceScore >= 0.7);

    console.log(`[recordDecisions] Found ${highConfidenceDecisions.length} high-confidence decisions`);

    // Persist decisions to Firestore
    const decisionsCollection = firestore
      .collection(COLLECTION_CONVERSATIONS)
      .doc(conversationId)
      .collection("decisions");

    const batch = firestore.batch();
    const persistedDecisions: Decision[] = [];
    const skippedDecisions: Decision[] = [];

    for (const decision of highConfidenceDecisions) {
      // Create a hash for deduplication
      const decisionHash = `${decision.decisionText.toLowerCase().slice(0, 50)}-${decision.decidedAt}`;
      const docId = Buffer.from(decisionHash).toString("base64").replace(/[/+=]/g, "").slice(0, 20);

      const decisionRef = decisionsCollection.doc(docId);
      const decisionDoc = await decisionRef.get();

      // Skip if already exists
      if (decisionDoc.exists) {
        console.log(`[recordDecisions] Decision ${docId} already exists, skipping`);
        skippedDecisions.push(decision);
        continue;
      }

      const decisionData = {
        ...decision,
        decidedAt: admin.firestore.Timestamp.fromDate(new Date(decision.decidedAt)),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      batch.set(decisionRef, decisionData);
      persistedDecisions.push(decision);
    }

    await batch.commit();

    console.log(`[recordDecisions] Persisted ${persistedDecisions.length} new decisions, skipped ${skippedDecisions.length} existing`);

    return {
      analyzed: highConfidenceDecisions.length,
      persisted: persistedDecisions.length,
      skipped: skippedDecisions.length,
      conversation_id: conversationId,
    };
  } catch (error) {
    console.error("[recordDecisions] Error:", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", "Failed to record decisions", error);
  }
});