import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2/options";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { Experimental_Agent as Agent } from "ai";
import { createOpenAI } from "@ai-sdk/openai";
import { tool } from "ai";
import { z } from "zod";
import { defineString } from "firebase-functions/params";

if (!admin.apps.length) {
  admin.initializeApp();
}

setGlobalOptions({ region: "us-central1" });

// Define OpenAI API key as an environment parameter
const openaiApiKey = defineString("OPENAI_API_KEY");

const firestore = admin.firestore();

type SampleContact = {
  id: string;
  displayName: string;
  email: string;
  avatarUrl?: string;
};

const SAMPLE_CONTACTS: SampleContact[] = [
  {
    id: "mock-alex",
    displayName: "Alex Rivera",
    email: "alex@example.com",
  },
  {
    id: "mock-priya",
    displayName: "Priya Patel",
    email: "priya@example.com",
  },
  {
    id: "mock-sam",
    displayName: "Sam Carter",
    email: "sam@example.com",
  },
  {
    id: "mock-jordan",
    displayName: "Jordan Smith",
    email: "jordan@example.com",
  },
];

const DELIVERY_SENT = "sent";
const COLLECTION_USERS = "users";
const COLLECTION_CONVERSATIONS = "conversations";
const SUBCOLLECTION_MESSAGES = "messages";
const DIRECT_INTRO_MESSAGE = "Hey there! Ready to build something great today?";

export const generateMockData = onCall(async (request) => {
  const uid = requireAuth(request);

  const timestamp = admin.firestore.Timestamp.now();

  await Promise.all(
    SAMPLE_CONTACTS.map(async (contact) => {
      const userRef = firestore.collection(COLLECTION_USERS).doc(contact.id);
      await userRef.set(
        {
          email: contact.email,
          displayName: contact.displayName,
          isOnline: false,
          lastSeen: timestamp,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    })
  );

  const conversationTasks: Array<Promise<unknown>> = [];

  const directContacts = SAMPLE_CONTACTS.slice(0, 2);
  for (const contact of directContacts) {
    conversationTasks.push(
      seedConversation({
        conversationId: deterministicConversationId("direct", [uid, contact.id]),
        participants: [uid, contact.id],
        isGroup: false,
        groupName: undefined,
      })
    );
  }

  const groupContacts = SAMPLE_CONTACTS.slice(0, 3);
  conversationTasks.push(
    seedConversation({
      conversationId: deterministicConversationId("group", [uid, ...groupContacts.map((c) => c.id)]),
      participants: [uid, ...groupContacts.map((c) => c.id)],
      isGroup: true,
      groupName: "Product Squad",
    })
  );

  await Promise.all(conversationTasks);

  return {
    status: "success",
    seeded: {
      direct: directContacts.length,
      group: 1,
    },
  };
});

export const getServerTime = onCall(async () => {
  const now = admin.firestore.Timestamp.now();
  return {
    iso: now.toDate().toISOString(),
    seconds: now.seconds,
    nanoseconds: now.nanoseconds,
  };
});

type SeedConversationArgs = {
  conversationId: string;
  participants: string[];
  isGroup: boolean;
  groupName?: string;
};

async function seedConversation({
  conversationId,
  participants,
  isGroup,
  groupName,
}: SeedConversationArgs) {
  const conversationRef = firestore.collection(COLLECTION_CONVERSATIONS).doc(conversationId);
  const now = admin.firestore.Timestamp.now();

  const adminId = participants[0];
  const messageCount = randomInt(1, 25);

  const orderedMessages: MockMessage[] = [];
  const senders = shuffleArray(participants);

  for (let i = 0; i < messageCount; i++) {
    const daysAgo = randomInt(0, 60);
    const secondsAgo = randomInt(0, 24 * 60 * 60);
    const timestampDate = new Date(Date.now() - (daysAgo * 24 * 60 * 60 + secondsAgo) * 1000);
    const sender = senders[i % senders.length];
    orderedMessages.push({
      senderId: sender,
      text: randomMessageText(sender),
      timestamp: timestampDate,
    });
  }

  orderedMessages.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());

  const lastMessage = orderedMessages[orderedMessages.length - 1];
  const unreadCounts = computeUnreadCounts(participants, lastMessage.senderId);

  const conversationData: Record<string, unknown> = {
    participantIds: participants,
    isGroup,
    adminIds: [adminId],
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    lastMessage: lastMessage.text,
    lastMessageTimestamp: admin.firestore.Timestamp.fromDate(lastMessage.timestamp),
    unreadCount: unreadCounts,
    mockSeeded: true,
  };

  if (groupName) {
    conversationData.groupName = groupName;
  }

  await conversationRef.set(conversationData, { merge: true });

  const messageWrites = orderedMessages.map((message) => {
    const messageId = firestore.collection("_").doc().id;
    const messageRef = conversationRef.collection(SUBCOLLECTION_MESSAGES).doc(messageId);
    return messageRef.set({
      conversationId,
      senderId: message.senderId,
      text: message.text,
      timestamp: admin.firestore.Timestamp.fromDate(message.timestamp),
      deliveryStatus: DELIVERY_SENT,
      readBy: [message.senderId],
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      mockSeeded: true,
    });
  });

  await Promise.all(messageWrites);
}

function deterministicConversationId(prefix: string, participantIds: string[]): string {
  const sorted = [...participantIds].sort();
  return `${prefix}-${sorted.join("-")}`;
}

type MockMessage = {
  senderId: string;
  text: string;
  timestamp: Date;
};

function randomInt(min: number, max: number): number {
  const lower = Math.ceil(min);
  const upper = Math.floor(max);
  return Math.floor(Math.random() * (upper - lower + 1)) + lower;
}

function shuffleArray<T>(array: T[]): T[] {
  const copy = [...array];
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

const MESSAGE_TEMPLATES = [
  "Quick sync?",
  "Let me know if you spot any issues.",
  "Great progress today!",
  "I'll tackle the next item on the list.",
  "Can we circle back on this later?",
  "Thanks for jumping in so quickly.",
  "Pushing an update now.",
  "I'll double-check the numbers.",
  "Looping in the team.",
  "Ship it! 🚀",
];

function randomMessageText(senderId: string): string {
  const base = MESSAGE_TEMPLATES[randomInt(0, MESSAGE_TEMPLATES.length - 1)];
  if (senderId.startsWith("mock-")) {
    return base;
  }
  return `${base} (from me)`;
}

function computeUnreadCounts(participants: string[], lastSender: string): Record<string, number> {
  const unread: Record<string, number> = {};
  participants.forEach((participant) => {
    unread[participant] = participant === lastSender ? 0 : randomInt(0, 3);
  });
  return unread;
}

export const deleteConversations = onCall(async (request) => {
  requireAuth(request);
  await admin.firestore().recursiveDelete(firestore.collection(COLLECTION_CONVERSATIONS));
  return { status: "success" };
});

export const deleteUsers = onCall(async (request) => {
  requireAuth(request);
  await admin.firestore().recursiveDelete(firestore.collection(COLLECTION_USERS));
  return { status: "success" };
});

function requireAuth<T>(request: CallableRequest<T>): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError(
      "unauthenticated",
      "Authentication is required for this operation."
    );
  }
  return uid;
}

// AI Agent Configuration
// API key is read from environment variable OPENAI_API_KEY
// For local dev: Add OPENAI_API_KEY to .env file
// For production: Set via Firebase console or deployment
const openai = createOpenAI({
  apiKey: openaiApiKey.value(),
});

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

// Push Notification Trigger
// Sends FCM push notifications when a new message is created
// Temporarily commented out - uncomment after Eventarc permissions propagate
/* export const sendMessageNotification = onDocumentCreated(
  "conversations/{conversationId}/messages/{messageId}",
  async (event) => {
    const messageData = event.data?.data();
    if (!messageData) {
      console.log("No message data found");
      return;
    }

    const conversationId = event.params.conversationId;
    const senderId = messageData.senderId as string;
    const messageText = messageData.text as string;

    console.log(`New message in conversation ${conversationId} from ${senderId}`);

    try {
      // Fetch conversation to get participants
      const conversationDoc = await firestore
        .collection(COLLECTION_CONVERSATIONS)
        .doc(conversationId)
        .get();

      if (!conversationDoc.exists) {
        console.log(`Conversation ${conversationId} not found`);
        return;
      }

      const conversationData = conversationDoc.data();
      const participantIds = conversationData?.participantIds as string[] || [];

      // Get recipients (exclude sender)
      const recipientIds = participantIds.filter((id) => id !== senderId);

      if (recipientIds.length === 0) {
        console.log("No recipients to notify");
        return;
      }

      // Fetch sender info
      const senderDoc = await firestore
        .collection(COLLECTION_USERS)
        .doc(senderId)
        .get();

      const senderName = senderDoc.exists
        ? (senderDoc.data()?.displayName as string || "Unknown")
        : "Unknown";

      // Fetch FCM tokens for all recipients
      const tokenPromises = recipientIds.map(async (recipientId) => {
        const userDoc = await firestore
          .collection(COLLECTION_USERS)
          .doc(recipientId)
          .get();

        if (!userDoc.exists) {
          return null;
        }

        const userData = userDoc.data();
        const fcmToken = userData?.fcmToken as string | undefined;

        if (!fcmToken) {
          console.log(`No FCM token for user ${recipientId}`);
          return null;
        }

        return { recipientId, fcmToken };
      });

      const tokenResults = await Promise.all(tokenPromises);
      const validTokens = tokenResults.filter(
        (result): result is { recipientId: string; fcmToken: string } =>
          result !== null
      );

      if (validTokens.length === 0) {
        console.log("No valid FCM tokens found for recipients");
        return;
      }

      // Send notifications to all recipients
      const notificationPromises = validTokens.map(async ({ fcmToken }) => {
        const message: admin.messaging.Message = {
          token: fcmToken,
          notification: {
            title: senderName,
            body: messageText.length > 100
              ? messageText.substring(0, 100) + "..."
              : messageText,
          },
          data: {
            conversationId: conversationId,
            senderId: senderId,
            type: "new_message",
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
                badge: 1,
              },
            },
          },
        };

        try {
          await admin.messaging().send(message);
          console.log(`Notification sent successfully to FCM token`);
        } catch (error) {
          console.error("Error sending notification:", error);
        }
      });

      await Promise.all(notificationPromises);
      console.log(`Sent ${notificationPromises.length} notifications`);
    } catch (error) {
      console.error("Error in sendMessageNotification:", error);
    }
  }
); */
