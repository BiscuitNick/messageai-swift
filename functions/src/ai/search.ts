import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { generateObject } from "ai";
import { openai } from "../core/config";
import { z } from "zod";

import { requireAuth } from "../core/auth";

const firestore = admin.firestore();
import { COLLECTION_CONVERSATIONS, SUBCOLLECTION_MESSAGES, COLLECTION_USERS, COLLECTION_BOTS } from "../core/constants";


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
import { fetchSenderNames } from "../core/utils";

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

  const systemPrompt = `You are a semantic search assistant that helps users find relevant messages in their conversations.\n\nYour task is to:\n1. Understand the user's search query intent\n2. Identify the most relevant messages based on semantic meaning, not just keyword matching\n3. Rank results by relevance\n4. Provide brief reasoning for why each message is relevant\n\nEach message is prefixed with [MSG-{index}] for reference.\nReturn the message indices (as messageId) of the most relevant messages, ordered by relevance (most relevant first).\nInclude a relevance score (0-1) and a brief snippet of the relevant content.\nLimit results to the ${maxResults} most relevant messages.`;

  const userPrompt = `Search query: \"${query}\"\n\nConversation messages:\n${searchContext}`;

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
