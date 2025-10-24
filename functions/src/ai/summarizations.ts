import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { generateObject } from "ai";
import { openai } from "../core/config";
import { z } from "zod";

import { requireAuth } from "../core/auth";

const firestore = admin.firestore();
import { COLLECTION_CONVERSATIONS, SUBCOLLECTION_MESSAGES, COLLECTION_USERS, COLLECTION_BOTS } from "../core/constants";


// Thread Summarization
// Summarizes a conversation thread by analyzing recent messages
type SummarizeThreadRequest = {
  conversationId: string;
  messageLimit?: number;
};

export const summarizeThreadTask = onCall<SummarizeThreadRequest>(async (request) => {
  const uid = requireAuth(request);

  const { conversationId, messageLimit = 50 } = request.data;

  if (!conversationId) {
    throw new HttpsError(
      "invalid-argument",
      "conversationId is required"
    );
  }

  try {
    // Verify conversation exists and user has access
    const conversationRef = firestore.collection(COLLECTION_CONVERSATIONS).doc(conversationId);
    const conversationDoc = await conversationRef.get();

    if (!conversationDoc.exists) {
      throw new HttpsError("not-found", "Conversation not found");
    }

    const conversationData = conversationDoc.data();
    const participantIds = conversationData?.participantIds as string[] || [];

    // Verify user is a participant
    if (!participantIds.includes(uid)) {
      throw new HttpsError("permission-denied", "User is not a participant in this conversation");
    }

    // Fetch recent messages
    const messagesSnapshot = await conversationRef
      .collection(SUBCOLLECTION_MESSAGES)
      .orderBy("timestamp", "desc")
      .limit(messageLimit)
      .get();

    if (messagesSnapshot.empty) {
      return {
        summary: "No messages to summarize.",
        key_points: [],
        conversation_id: conversationId,
        timestamp: new Date().toISOString(),
        message_count: 0,
      };
    }

    // Build messages array (reverse to chronological order)
    const messages = messagesSnapshot.docs.reverse().map((doc) => {
      const data = doc.data();
      return {
        senderId: data.senderId as string,
        text: data.text as string,
        timestamp: (data.timestamp as admin.firestore.Timestamp).toDate(),
      };
    });

    // Fetch participant names for context
    const uniqueSenderIds = [...new Set(messages.map(m => m.senderId))];
    const senderNames: Record<string, string> = {};

    await Promise.all(
      uniqueSenderIds.map(async (senderId) => {
        // Handle bot participants
        if (senderId.startsWith("bot:")) {
          const botId = senderId.replace("bot:", "");
          const botDoc = await firestore.collection(COLLECTION_BOTS).doc(botId).get();
          if (botDoc.exists) {
            senderNames[senderId] = botDoc.data()?.name as string || "Bot";
          } else {
            senderNames[senderId] = "Bot";
          }
        } else {
          const userDoc = await firestore.collection(COLLECTION_USERS).doc(senderId).get();
          if (userDoc.exists) {
            senderNames[senderId] = userDoc.data()?.displayName as string || "Unknown";
          } else {
            senderNames[senderId] = "Unknown";
          }
        }
      })
    );

    // Build summary prompt
    const conversationText = messages
      .map((msg) => `${senderNames[msg.senderId]}: ${msg.text}`)
      .join("\n");

    const systemPrompt = `You are an AI assistant that creates concise summaries of conversation threads.\nYour goal is to:\n1. Identify the main topics and key points discussed\n2. Highlight any decisions made\n3. Note any action items or next steps\n4. Capture important updates or announcements\n5. Keep the summary brief and focused\n\nFormat your response as a JSON object with:\n- summary: A 2-3 sentence overview of the conversation\n- keyPoints: An array of 3-5 key points or highlights (strings)`;

    const userPrompt = `Summarize the following conversation:\n\n${conversationText}`;

    // Define the response schema for structured output
    const summarySchema = z.object({
      summary: z.string().describe("A 2-3 sentence overview of the conversation"),
      keyPoints: z.array(z.string()).describe("An array of 3-5 key points or highlights"),
    });

    

    // Call OpenAI for summarization using Vercel AI SDK
    const { object: summaryData } = await generateObject({
      model: openai("gpt-4o-mini"),
      system: systemPrompt,
      prompt: userPrompt,
      schema: summarySchema,
      temperature: 0.3,
    });

    // Format response matching ThreadSummaryResponse DTO
    return {
      summary: summaryData.summary || "Summary not available.",
      key_points: summaryData.keyPoints || [],
      conversation_id: conversationId,
      timestamp: new Date().toISOString(),
      message_count: messages.length,
    };
  } catch (error) {
    console.error("Summarization error:", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError(
      "internal",
      "Failed to summarize conversation",
      error
    );
  }
});
