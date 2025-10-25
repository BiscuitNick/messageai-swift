import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Experimental_Agent as Agent } from "ai";
import { openai } from "../core/config";
import { tool } from "ai";
import { z } from "zod";

import { requireAuth } from "../core/auth";

const firestore = admin.firestore();
import { COLLECTION_CONVERSATIONS, SUBCOLLECTION_MESSAGES, DELIVERY_SENT } from "../core/constants";

// AI Agent Configuration


const assistantAgent = new Agent({
  model: openai("gpt-4o-mini"),
  system: `You are a helpful assistant integrated into a messaging application.
Your role is to help users with various tasks including:
- Answering questions
- Providing recommendations
- Drafting messages
- Summarizing conversations
- General assistance

Always be concise, friendly, and helpful. Keep responses brief unless detailed information is requested.`,
  tools: {
    getCurrentTime: tool({
      description: "Get the current date and time",
      inputSchema: z.object({}),
      execute: async () => {
        const now = new Date();
        return {
          timestamp: now.toISOString(),
          formatted: now.toLocaleString("en-US", {
            weekday: "long",
            year: "numeric",
            month: "long",
            day: "numeric",
            hour: "2-digit",
            minute: "2-digit",
          }),
        };
      },
    }),
    draftMessage: tool({
      description: "Draft a message based on user requirements",
      inputSchema: z.object({
        tone: z.enum(["professional", "casual", "friendly", "formal"]).describe("The tone of the message"),
        purpose: z.string().describe("The purpose or topic of the message"),
        length: z.enum(["short", "medium", "long"]).optional().describe("Desired message length"),
      }),
      execute: async ({ tone, purpose, length = "medium" }) => {
        return {
          suggestion: `I'll help you draft a ${tone} message about ${purpose}. Length preference: ${length}`,
          tone,
          purpose,
        };
      },
    }),
  },
});

type AgentMessage = {
  role: "user" | "assistant";
  content: string;
};

type AgentRequest = {
  messages: AgentMessage[];
  conversationId: string;
};

export const chatWithAgent = onCall<AgentRequest>(async (request) => {
  const uid = requireAuth(request);

  const { messages = [], conversationId } = request.data;

  if (messages.length === 0) {
    throw new HttpsError(
      "invalid-argument",
      "messages array is required"
    );
  }

  if (!conversationId) {
    throw new HttpsError(
      "invalid-argument",
      "conversationId is required"
    );
  }

  try {
    // Get conversation to find which bot is being used
    const conversationRef = firestore.collection(COLLECTION_CONVERSATIONS).doc(conversationId);
    const conversationDoc = await conversationRef.get();
    const conversationData = conversationDoc.data();

    if (!conversationData) {
      throw new HttpsError("not-found", "Conversation not found");
    }

    // Find the bot participant (format: "bot:botId")
    const botParticipant = conversationData.participantIds.find((id: string) =>
      id.startsWith("bot:")
    );

    if (!botParticipant) {
      throw new HttpsError("invalid-argument", "No bot found in conversation");
    }

    // Extract bot ID from "bot:botId" format
    const botId = botParticipant.replace("bot:", "");

    // Get bot configuration from bots collection
    const botDoc = await firestore.collection("bots").doc(botId).get();
    const botData = botDoc.data();

    if (!botData) {
      throw new HttpsError("not-found", "Bot configuration not found");
    }

    // Generate response with bot's system prompt and configuration
    const result = await assistantAgent.generate({
      messages: messages.map((msg) => ({
        role: msg.role,
        content: msg.content,
      })),
      system: botData.systemPrompt || "You are a helpful AI assistant.",
    });

    const responseText = result.text;
    const timestamp = admin.firestore.Timestamp.now();

    // Write bot response directly to Firestore with prefixed bot ID
    const messageId = firestore.collection("_").doc().id;
    const messageRef = conversationRef.collection(SUBCOLLECTION_MESSAGES).doc(messageId);

    await messageRef.set({
      conversationId,
      senderId: botParticipant, // Use full "bot:botId" format
      text: responseText,
      timestamp,
      deliveryStatus: DELIVERY_SENT,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Update conversation metadata
    const lastInteractionByUser = conversationData.lastInteractionByUser || {};
    lastInteractionByUser[botParticipant] = timestamp;

    await conversationRef.set({
      lastMessage: responseText,
      lastMessageTimestamp: timestamp,
      lastSenderId: botParticipant,
      lastInteractionByUser,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return {
      response: responseText,
      usage: result.usage,
    };
  } catch (error) {
    console.error("Agent error:", error);
    throw new HttpsError(
      "internal",
      "Failed to process agent request",
      error
    );
  }
});
