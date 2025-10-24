import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2/options";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { Experimental_Agent as Agent, generateObject } from "ai";
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
const COLLECTION_BOTS = "bots";
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

export const createBots = onCall(async (request) => {
  requireAuth(request);

  const botsRef = firestore.collection("bots");
  const timestamp = admin.firestore.FieldValue.serverTimestamp();

  // Create Dash Bot
  await botsRef.doc("dash-bot").set({
    name: "Dash Bot",
    description: "I can help you with answering questions, drafting messages, providing recommendations, and more. What can I help you with today?",
    avatarURL: "https://dpj39bucz99gb.cloudfront.net/n8qq1sycd9rg80ct1zbrfw5k58",
    category: "general",
    capabilities: ["conversation", "question-answering", "recommendations", "drafting"],
    model: "gpt-4o",
    systemPrompt: "You are Dash Bot, a helpful AI assistant. Be concise, friendly, and accurate.",
    tools: [],
    isActive: true,
    updatedAt: timestamp,
    createdAt: timestamp,
  }, { merge: true });

  // Create Dad Bot
  await botsRef.doc("dad-bot").set({
    name: "Dad Bot",
    description: "Your go-to source for dad jokes and fatherly advice. Need a laugh or some wisdom? I've got you covered!",
    avatarURL: "https://dpj39bucz99gb.cloudfront.net/n8qq1sycd9rg80ct1zbrfw5k58",
    category: "humor",
    capabilities: ["dad-jokes", "advice", "conversation"],
    model: "gpt-4o",
    systemPrompt: "You are Dad Bot, a friendly AI that specializes in dad jokes and fatherly advice. When users explicitly ask for advice, provide thoughtful, encouraging fatherly guidance. When users explicitly ask for a joke, respond with a relevant dad joke. Otherwise, use your best judgment to determine whether the situation calls for humor or wisdom - consider the tone and context of their message. Keep responses warm, wholesome, and appropriately cheesy.",
    tools: [],
    isActive: true,
    updatedAt: timestamp,
    createdAt: timestamp,
  }, { merge: true });

  return {
    status: "success",
    created: ["dash-bot", "dad-bot"]
  };
});

export const deleteBots = onCall(async (request) => {
  requireAuth(request);
  await admin.firestore().recursiveDelete(firestore.collection("bots"));
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
          const botDoc = await firestore.collection("bots").doc(botId).get();
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

    const systemPrompt = `You are an AI assistant that creates concise summaries of conversation threads.
Your goal is to:
1. Identify the main topics and key points discussed
2. Highlight any decisions made
3. Note any action items or next steps
4. Capture important updates or announcements
5. Keep the summary brief and focused

Format your response as a JSON object with:
- summary: A 2-3 sentence overview of the conversation
- keyPoints: An array of 3-5 key points or highlights (strings)`;

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
 * Callable function to extract action items from recent conversation messages
 * Uses OpenAI to analyze messages and identify actionable tasks with metadata
 */
export const extractActionItems = onCall<ExtractActionItemsRequest>(async (request) => {
  const uid = requireAuth(request);
  const { conversationId, windowDays = 7 } = request.data;

  try {
    // Verify user is a participant in the conversation
    const conversationRef = firestore.collection(COLLECTION_CONVERSATIONS).doc(conversationId);
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

    // Calculate the cutoff date for the time window
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - windowDays);

    // Fetch messages from the last N days
    const messagesSnapshot = await conversationRef
      .collection("messages")
      .where("timestamp", ">=", cutoffDate)
      .orderBy("timestamp", "asc")
      .limit(100) // Limit to prevent excessive token usage
      .get();

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
    const systemPrompt = `You are an AI assistant specialized in extracting action items and tasks from conversation messages.

Your task is to analyze the conversation and identify:
1. Explicit action items (tasks someone said they would do)
2. Implied commitments or responsibilities
3. Deadlines or time-sensitive items
4. Assigned tasks (who is responsible)
5. Priorities based on context

For each action item, determine:
- A clear, concise description of the task
- Who it's assigned to (if mentioned)
- When it's due (if mentioned)
- The priority level (low, medium, high, urgent)
- Current status (pending by default, unless mentioned as in-progress or completed)

Generate a unique ID for each action item using a combination of timestamp and index.
Format due dates as ISO 8601 strings if dates are mentioned.
If an assignee is mentioned by name, try to match it to a participant in the conversation.

Only extract genuine action items - ignore casual mentions or hypothetical discussions.`;

    const userPrompt = `Analyze the following conversation and extract all action items:\n\n${conversationText}`;

    console.log(`[extractActionItems] Analyzing ${conversationText.split('\n').length} lines of conversation`);

    // Call OpenAI for action item extraction using Vercel AI SDK
    const { object: extractedData } = await generateObject({
      model: openai("gpt-4o-mini"),
      system: systemPrompt,
      prompt: userPrompt,
      schema: actionItemsResponseSchema,
      temperature: 0.2, // Lower temperature for more deterministic extraction
    });

    console.log(`[extractActionItems] OpenAI found ${extractedData.actionItems.length} action items`);

    // Format response and persist to Firestore
    const actionItems = extractedData.actionItems.map((item, index) => ({
      id: item.id || `action-${Date.now()}-${index}`,
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
    const batch = firestore.batch();
    const actionItemsRef = conversationRef.collection("actionItems");

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

    await batch.commit();

    console.log(`[extractActionItems] Persisted ${actionItems.length} action items to Firestore`);

    return {
      action_items: actionItems,
      conversation_id: conversationId,
      window_days: windowDays,
      message_count: messages.length,
    };
  } catch (error) {
    console.error("Action item extraction error:", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError(
      "internal",
      "Failed to extract action items",
      error
    );
  }
});

// ============================================================================
// AI Feature: Semantic Smart Search
// ============================================================================

interface SmartSearchRequest {
  query: string;
  maxResults?: number; // Default: 20
}

interface SearchHit {
  id: string;
  conversationId: string;
  messageId: string;
  snippet: string;
  rank: number;
  timestamp: string;
}

interface GroupedSearchResult {
  conversationId: string;
  hits: SearchHit[];
}

interface MessageData {
  conversationId: string;
  messageId: string;
  senderId: string;
  text: string;
  timestamp: Date;
}

// Define the search result schema using Zod
const searchHitSchema = z.object({
  messageId: z.string().describe("ID of the message containing the relevant content"),
  snippet: z.string().describe("Relevant excerpt from the message"),
  relevanceScore: z.number().min(0).max(1).describe("Relevance score between 0 and 1"),
  reasoning: z.string().optional().describe("Brief explanation of why this message is relevant"),
});

const searchResultsSchema = z.object({
  results: z.array(searchHitSchema).describe("List of search results ranked by relevance"),
});

/**
 * Helper: Collect recent messages from user's conversations
 */
async function collectMessages(
  uid: string,
  messagesPerConversation: number = 50
): Promise<MessageData[]> {
  // Fetch all conversations where user is a participant
  const conversationsSnapshot = await firestore
    .collection(COLLECTION_CONVERSATIONS)
    .where("participantIds", "array-contains", uid)
    .get();

  if (conversationsSnapshot.empty) {
    return [];
  }

  const conversationIds = conversationsSnapshot.docs.map((doc) => doc.id);
  const allMessages: MessageData[] = [];

  // Collect messages from each conversation
  const messagePromises = conversationIds.map(async (conversationId) => {
    const messagesSnapshot = await firestore
      .collection(COLLECTION_CONVERSATIONS)
      .doc(conversationId)
      .collection(SUBCOLLECTION_MESSAGES)
      .orderBy("timestamp", "desc")
      .limit(messagesPerConversation)
      .get();

    return messagesSnapshot.docs.map((doc) => {
      const data = doc.data();
      return {
        conversationId,
        messageId: doc.id,
        senderId: data.senderId as string,
        text: data.text as string,
        timestamp: (data.timestamp as admin.firestore.Timestamp).toDate(),
      };
    });
  });

  const messagesArrays = await Promise.all(messagePromises);
  messagesArrays.forEach((messages) => allMessages.push(...messages));

  return allMessages;
}

/**
 * Helper: Fetch display names for message senders (users and bots)
 */
async function fetchSenderNames(senderIds: string[]): Promise<Record<string, string>> {
  const senderNames: Record<string, string> = {};

  await Promise.all(
    senderIds.map(async (senderId) => {
      if (senderId.startsWith("bot:")) {
        const botId = senderId.replace("bot:", "");
        const botDoc = await firestore.collection(COLLECTION_BOTS).doc(botId).get();
        senderNames[senderId] = botDoc.exists ? (botDoc.data()?.name as string || "Bot") : "Bot";
      } else {
        const userDoc = await firestore.collection(COLLECTION_USERS).doc(senderId).get();
        senderNames[senderId] = userDoc.exists
          ? (userDoc.data()?.displayName as string || "Unknown")
          : "Unknown";
      }
    })
  );

  return senderNames;
}

/**
 * Helper: Build search context and prompts for OpenAI
 */
function buildSearchPrompt(
  query: string,
  messages: MessageData[],
  senderNames: Record<string, string>,
  maxResults: number
): { systemPrompt: string; userPrompt: string } {
  // Build search context with message indices
  const searchContext = messages
    .map((msg, index) => {
      const senderName = senderNames[msg.senderId] || "Unknown";
      return `[MSG-${index}] [${senderName}]: ${msg.text}`;
    })
    .join("\n");

  const systemPrompt = `You are a semantic search assistant that helps users find relevant messages in their conversations.

Your task is to:
1. Understand the user's search query intent
2. Identify the most relevant messages based on semantic meaning, not just keyword matching
3. Rank results by relevance
4. Provide brief reasoning for why each message is relevant

Each message is prefixed with [MSG-{index}] for reference.
Return the message indices (as messageId) of the most relevant messages, ordered by relevance (most relevant first).
Include a relevance score (0-1) and a brief snippet of the relevant content.
Limit results to the ${maxResults} most relevant messages.`;

  const userPrompt = `Search query: "${query}"\n\nConversation messages:\n${searchContext}`;

  return { systemPrompt, userPrompt };
}

/**
 * Helper: Map OpenAI search results back to actual message data
 */
function normalizeSearchHits(
  searchResults: Array<{ messageId: string; snippet: string }>,
  messages: MessageData[],
  maxResults: number
): SearchHit[] {
  const searchHits: SearchHit[] = searchResults
    .slice(0, maxResults)
    .map((result, rank) => {
      // Extract index from messageId (format: "MSG-{index}")
      const indexMatch = result.messageId.match(/MSG-(\d+)/);
      if (!indexMatch) return null;

      const messageIndex = parseInt(indexMatch[1], 10);
      if (messageIndex >= messages.length) return null;

      const message = messages[messageIndex];
      return {
        id: `${message.conversationId}-${message.messageId}`,
        conversationId: message.conversationId,
        messageId: message.messageId,
        snippet: result.snippet,
        rank: rank + 1,
        timestamp: message.timestamp.toISOString(),
      };
    })
    .filter((hit): hit is SearchHit => hit !== null);

  return searchHits;
}

/**
 * Helper: Group search hits by conversation
 */
function groupResultsByConversation(searchHits: SearchHit[]): GroupedSearchResult[] {
  const groupedMap = new Map<string, SearchHit[]>();

  searchHits.forEach((hit) => {
    if (!groupedMap.has(hit.conversationId)) {
      groupedMap.set(hit.conversationId, []);
    }
    groupedMap.get(hit.conversationId)!.push(hit);
  });

  return Array.from(groupedMap.entries()).map(([conversationId, hits]) => ({
    conversationId,
    hits: hits.sort((a, b) => a.rank - b.rank),
  }));
}

/**
 * Callable function for semantic search across user's conversations
 * Uses OpenAI to understand query intent and find relevant messages
 */
export const smartSearch = onCall<SmartSearchRequest>(async (request) => {
  const uid = requireAuth(request);
  const { query, maxResults = 20 } = request.data;

  if (!query || query.trim().length === 0) {
    throw new HttpsError("invalid-argument", "Search query is required");
  }

  try {
    // 1. Collect messages from user's conversations
    const allMessages = await collectMessages(uid);

    if (allMessages.length === 0) {
      return {
        grouped_results: [],
        query,
        total_hits: 0,
      };
    }

    // 2. Fetch sender names for context
    const uniqueSenderIds = [...new Set(allMessages.map((m) => m.senderId))];
    const senderNames = await fetchSenderNames(uniqueSenderIds);

    // 3. Build search prompts
    const { systemPrompt, userPrompt } = buildSearchPrompt(
      query,
      allMessages,
      senderNames,
      maxResults
    );

    // 4. Call OpenAI for semantic search
    const { object: searchData } = await generateObject({
      model: openai("gpt-4o-mini"),
      system: systemPrompt,
      prompt: userPrompt,
      schema: searchResultsSchema,
      temperature: 0.2,
    });

    // 5. Normalize results back to message data
    const searchHits = normalizeSearchHits(searchData.results, allMessages, maxResults);

    // 6. Group results by conversation
    const groupedResults = groupResultsByConversation(searchHits);

    return {
      grouped_results: groupedResults,
      query,
      total_hits: searchHits.length,
    };
  } catch (error) {
    console.error("Smart search error:", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", "Failed to perform smart search", error);
  }
});

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
 * Classifies message priority using OpenAI
 */
async function classifyMessagePriority(messageText: string): Promise<PriorityClassification> {
  const openai = createOpenAI({
    apiKey: openaiApiKey.value(),
  });

  const systemPrompt = `You are a message priority classifier. Analyze the given message and assign a priority score and label based on urgency, importance, and time-sensitivity.

Priority Guidelines:
- Score 1 (low): Casual conversation, FYI messages, non-urgent updates
- Score 2 (medium-low): General questions, routine requests
- Score 3 (medium): Actionable items, scheduled tasks, normal business
- Score 4 (high): Time-sensitive requests, important decisions needed soon
- Score 5 (urgent/critical): Immediate action required, emergencies, blocking issues

Consider:
- Urgency indicators (ASAP, urgent, now, immediately)
- Question marks (questions often need responses)
- Action verbs (need, require, must)
- Time constraints (today, deadline, by EOD)
- Emotional tone (stressed, frustrated)`;

  const userPrompt = `Classify this message:\n\n"${messageText}"`;

  const { object: classification } = await generateObject({
    model: openai("gpt-4o-mini"),
    system: systemPrompt,
    prompt: userPrompt,
    schema: priorityClassificationSchema,
    temperature: 0.3,
  });

  return classification;
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
      .collection(SUBCOLLECTION_MESSAGES)
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
    const openai = createOpenAI({
      apiKey: openaiApiKey.value(),
    });

    const systemPrompt = `You are a decision tracking assistant. Analyze the conversation transcript and identify any decisions that were made.

A decision is:
- A concrete choice or commitment made by participants
- Something actionable or that changes plans/direction
- Not just a suggestion or possibility, but a finalized choice

For each decision, provide:
- The decision text (what was decided)
- Context summary (why it was decided)
- Participant IDs of those involved
- Timestamp when it was decided
- Follow-up status (pending by default)
- Confidence score (how certain you are this is a real decision)

Only include decisions with confidence >= 0.7`;

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
  const openai = createOpenAI({
    apiKey: openaiApiKey.value(),
  });

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

  const userPrompt = `Classify this message for scheduling intent:\n\n"${messageText}"`;

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

// ============================================================================
// AI Feature: Meeting Time Suggestions
// ============================================================================

interface SuggestMeetingTimesRequest {
  conversationId: string;
  participantIds: string[];
  durationMinutes: number;
  preferredDays?: number; // How many days out to suggest (default: 14)
}

interface MeetingSuggestion {
  startTime: string; // ISO 8601 timestamp
  endTime: string; // ISO 8601 timestamp
  score: number; // 0-1 relevance score
  justification: string; // Why this time works
  dayOfWeek: string;
  timeOfDay: string; // e.g., "morning", "afternoon", "evening"
}

// Zod schema for meeting suggestion response
const meetingSuggestionSchema = z.object({
  startTime: z.string().describe("ISO 8601 timestamp for meeting start"),
  endTime: z.string().describe("ISO 8601 timestamp for meeting end"),
  score: z.number().min(0).max(1).describe("Relevance score 0-1"),
  justification: z.string().describe("Explanation of why this time slot works well"),
  dayOfWeek: z.string().describe("Day of the week (e.g., Monday, Tuesday)"),
  timeOfDay: z.enum(["morning", "afternoon", "evening"]).describe("General time of day"),
});

const meetingSuggestionsResponseSchema = z.object({
  suggestions: z.array(meetingSuggestionSchema)
    .min(3)
    .max(5)
    .describe("3-5 ranked meeting time suggestions"),
});

/**
 * Helper: Analyze participant message activity patterns
 */
async function analyzeParticipantActivity(
  participantIds: string[]
): Promise<{
  hourlyActivity: Record<number, number>; // hour (0-23) -> message count
  dayOfWeekActivity: Record<string, number>; // day name -> message count
  activeTimezoneOffset: number; // guessed timezone offset in minutes
}> {
  const hourlyActivity: Record<number, number> = {};
  const dayOfWeekActivity: Record<string, number> = {};

  // Initialize counters
  for (let hour = 0; hour < 24; hour++) {
    hourlyActivity[hour] = 0;
  }
  const daysOfWeek = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  daysOfWeek.forEach(day => {
    dayOfWeekActivity[day] = 0;
  });

  // Collect messages from all participants
  const messagePromises = participantIds.map(async (participantId) => {
    // Skip bot participants
    if (participantId.startsWith("bot:")) {
      return [];
    }

    // Query conversations where this participant is involved
    const conversationsSnapshot = await firestore
      .collection(COLLECTION_CONVERSATIONS)
      .where("participantIds", "array-contains", participantId)
      .limit(10) // Limit conversations to avoid excessive queries
      .get();

    const participantMessages: Date[] = [];

    // Collect messages from each conversation
    for (const convDoc of conversationsSnapshot.docs) {
      const messagesSnapshot = await firestore
        .collection(COLLECTION_CONVERSATIONS)
        .doc(convDoc.id)
        .collection(SUBCOLLECTION_MESSAGES)
        .where("senderId", "==", participantId)
        .orderBy("timestamp", "desc")
        .limit(50) // Sample recent messages
        .get();

      messagesSnapshot.docs.forEach((msgDoc) => {
        const data = msgDoc.data();
        const timestamp = (data.timestamp as admin.firestore.Timestamp)?.toDate();
        if (timestamp) {
          participantMessages.push(timestamp);
        }
      });
    }

    return participantMessages;
  });

  const allParticipantMessages = await Promise.all(messagePromises);
  const allTimestamps = allParticipantMessages.flat();

  // Analyze message timestamps
  allTimestamps.forEach((timestamp) => {
    const hour = timestamp.getHours();
    const dayOfWeek = daysOfWeek[timestamp.getDay()];

    hourlyActivity[hour] = (hourlyActivity[hour] || 0) + 1;
    dayOfWeekActivity[dayOfWeek] = (dayOfWeekActivity[dayOfWeek] || 0) + 1;
  });

  // Estimate timezone offset based on activity patterns
  // Find peak activity hour
  let peakHour = 12; // default to noon
  let maxActivity = 0;
  Object.entries(hourlyActivity).forEach(([hour, count]) => {
    if (count > maxActivity) {
      maxActivity = count;
      peakHour = parseInt(hour);
    }
  });

  // Assume peak activity is around 2pm local time (14:00)
  const estimatedLocalHour = 14;
  const timezoneOffset = (peakHour - estimatedLocalHour) * 60; // in minutes

  return {
    hourlyActivity,
    dayOfWeekActivity,
    activeTimezoneOffset: timezoneOffset,
  };
}

/**
 * Callable function to suggest meeting times based on participant availability
 */
export const suggestMeetingTimes = onCall<SuggestMeetingTimesRequest>(async (request) => {
  const uid = requireAuth(request);
  const { conversationId, participantIds, durationMinutes, preferredDays = 14 } = request.data;

  if (!conversationId) {
    throw new HttpsError("invalid-argument", "conversationId is required");
  }

  if (!participantIds || participantIds.length === 0) {
    throw new HttpsError("invalid-argument", "participantIds array is required");
  }

  if (!durationMinutes || durationMinutes <= 0) {
    throw new HttpsError("invalid-argument", "durationMinutes must be a positive number");
  }

  console.log(`[suggestMeetingTimes] Suggesting times for ${participantIds.length} participants, ${durationMinutes}min duration`);

  try {
    // Verify conversation exists and user has access
    const conversationDoc = await firestore
      .collection(COLLECTION_CONVERSATIONS)
      .doc(conversationId)
      .get();

    if (!conversationDoc.exists) {
      throw new HttpsError("not-found", "Conversation not found");
    }

    const conversationData = conversationDoc.data();
    const conversationParticipants = conversationData?.participantIds as string[] || [];

    if (!conversationParticipants.includes(uid)) {
      throw new HttpsError("permission-denied", "User is not a participant in this conversation");
    }

    // Analyze participant activity patterns
    const activityAnalysis = await analyzeParticipantActivity(participantIds);

    // Fetch participant names for context
    const participantNames = await fetchSenderNames(participantIds);

    // Build context for OpenAI
    const participantContext = participantIds
      .map(id => `- ${participantNames[id] || id}`)
      .join("\n");

    // Find top active hours
    const topHours = Object.entries(activityAnalysis.hourlyActivity)
      .sort(([, a], [, b]) => b - a)
      .slice(0, 5)
      .map(([hour]) => parseInt(hour));

    // Find top active days
    const topDays = Object.entries(activityAnalysis.dayOfWeekActivity)
      .sort(([, a], [, b]) => b - a)
      .slice(0, 3)
      .map(([day]) => day);

    const now = new Date();
    const endDate = new Date(now);
    endDate.setDate(endDate.getDate() + preferredDays);

    const systemPrompt = `You are a meeting scheduling assistant that suggests optimal meeting times based on participant activity patterns.

Your task is to suggest 3-5 meeting time slots that maximize the likelihood of participant availability.

Consider:
1. Historical activity patterns (when participants are typically active)
2. Standard business hours and timezone considerations
3. Avoiding early mornings, late evenings, and weekends unless activity suggests otherwise
4. Meeting duration requirements
5. Providing a mix of options (different days/times)

For each suggestion:
- Provide exact start and end times as ISO 8601 timestamps
- Score the suggestion (0-1) based on how well it matches activity patterns
- Justify why this time works well
- Identify the day of week and general time of day

Current date: ${now.toISOString()}
Suggestion window: Next ${preferredDays} days (until ${endDate.toISOString()})`;

    const userPrompt = `Suggest ${durationMinutes}-minute meeting times for these participants:

${participantContext}

Activity Analysis:
- Most active hours (UTC): ${topHours.join(", ")}
- Most active days: ${topDays.join(", ")}
- Estimated timezone offset: ${activityAnalysis.activeTimezoneOffset} minutes from UTC

Generate 3-5 ranked meeting time suggestions within the next ${preferredDays} days.`;

    console.log(`[suggestMeetingTimes] Calling OpenAI with activity patterns: top hours [${topHours}], top days [${topDays}]`);

    // Call OpenAI for meeting suggestions
    const { object: response } = await generateObject({
      model: openai("gpt-4o-mini"),
      system: systemPrompt,
      prompt: userPrompt,
      schema: meetingSuggestionsResponseSchema,
      temperature: 0.7, // Allow some creativity in suggestions
    });

    console.log(`[suggestMeetingTimes] Generated ${response.suggestions.length} meeting suggestions`);

    // Format response
    const suggestions: MeetingSuggestion[] = response.suggestions.map((s, index) => ({
      startTime: s.startTime,
      endTime: s.endTime,
      score: s.score,
      justification: s.justification,
      dayOfWeek: s.dayOfWeek,
      timeOfDay: s.timeOfDay,
    }));

    // Sort by score descending
    suggestions.sort((a, b) => b.score - a.score);

    // Track analytics for suggestion generation
    try {
      const analyticsRef = firestore.collection("analytics").doc("meetingSuggestions");
      await analyticsRef.set({
        totalRequests: admin.firestore.FieldValue.increment(1),
        totalSuggestionsGenerated: admin.firestore.FieldValue.increment(suggestions.length),
        lastRequestAt: admin.firestore.FieldValue.serverTimestamp(),
        averageParticipantCount: admin.firestore.FieldValue.increment(participantIds.length),
        averageDurationMinutes: admin.firestore.FieldValue.increment(durationMinutes),
      }, { merge: true });

      // Also track individual request details
      await analyticsRef.collection("requests").add({
        conversationId,
        participantCount: participantIds.length,
        durationMinutes,
        suggestionsCount: suggestions.length,
        topSuggestionScore: suggestions[0]?.score || 0,
        requestedBy: uid,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`[suggestMeetingTimes] Analytics recorded for request`);
    } catch (analyticsError) {
      // Don't fail the request if analytics fails
      console.error("[suggestMeetingTimes] Analytics error (non-fatal):", analyticsError);
    }

    return {
      suggestions,
      conversation_id: conversationId,
      duration_minutes: durationMinutes,
      participant_count: participantIds.length,
      generated_at: new Date().toISOString(),
      expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(), // 24 hours
    };
  } catch (error) {
    console.error("[suggestMeetingTimes] Error:", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", "Failed to suggest meeting times", error);
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
