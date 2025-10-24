import * as admin from "firebase-admin";
import { generateObject } from "ai";
import { openai } from "../core/config";
import { z } from "zod";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { COLLECTION_CONVERSATIONS, SUBCOLLECTION_MESSAGES } from "../core/constants";

const firestore = admin.firestore();

// ============================================================================
// Coordination Insights Schema
// ============================================================================

const coordinationInsightSchema = z.object({
  actionItems: z.array(z.object({
    description: z.string().describe("Description of the action item"),
    assignee: z.string().optional().describe("Person assigned if mentioned"),
    deadline: z.string().optional().describe("Deadline if mentioned"),
    status: z.enum(["unresolved", "pending", "resolved"]).describe("Status of the action item"),
  })).describe("Action items found in the conversation"),

  staleDacisions: z.array(z.object({
    topic: z.string().describe("Topic of the decision"),
    lastMentioned: z.string().describe("When it was last mentioned"),
    reason: z.string().describe("Why it's considered stale"),
  })).describe("Decisions that haven't been followed up on"),

  upcomingDeadlines: z.array(z.object({
    description: z.string().describe("Description of the deadline"),
    dueDate: z.string().describe("When the deadline is"),
    urgency: z.enum(["low", "medium", "high", "critical"]).describe("Urgency level"),
  })).describe("Upcoming deadlines mentioned"),

  schedulingConflicts: z.array(z.object({
    description: z.string().describe("Description of the conflict"),
    participants: z.array(z.string()).describe("People involved"),
  })).describe("Potential scheduling conflicts detected"),

  blockers: z.array(z.object({
    description: z.string().describe("Description of the blocker"),
    blockedBy: z.string().optional().describe("What or who is blocking"),
  })).describe("Blockers mentioned in conversations"),

  summary: z.string().describe("Brief summary of coordination status"),
  overallHealth: z.enum(["good", "attention_needed", "critical"]).describe("Overall team coordination health"),
});

export type CoordinationInsight = z.infer<typeof coordinationInsightSchema>;

// ============================================================================
// Coordination Analysis
// ============================================================================

/**
 * Analyzes a conversation for coordination insights
 */
async function analyzeConversation(
  conversationId: string,
  messages: FirebaseFirestore.DocumentData[]
): Promise<CoordinationInsight | null> {
  if (messages.length === 0) {
    return null;
  }

  // Build conversation context
  const conversationText = messages
    .slice(-50) // Analyze last 50 messages max
    .map(msg => {
      const sender = msg.senderId?.replace("bot:", "Bot ") || "Unknown";
      const timestamp = msg.timestamp?.toDate().toISOString() || "";
      return `[${timestamp}] ${sender}: ${msg.text}`;
    })
    .join("\n");

  const systemPrompt = `You are a team coordination analyst. Analyze conversations to identify:
1. Unresolved action items and tasks
2. Stale decisions that haven't been followed up
3. Upcoming deadlines and time-sensitive items
4. Scheduling conflicts or coordination issues
5. Blockers preventing progress

Focus on extracting actionable coordination insights. Be conservative - only flag items with clear evidence.
Current date/time context: ${new Date().toISOString()}`;

  const userPrompt = `Analyze this conversation for coordination insights:

${conversationText}

Extract action items, stale decisions, deadlines, conflicts, and blockers. Provide a health assessment.`;

  try {
    const { object: insight } = await generateObject({
      model: openai("gpt-4o-mini"),
      system: systemPrompt,
      prompt: userPrompt,
      schema: coordinationInsightSchema,
      temperature: 0.3,
    });

    return insight;
  } catch (error) {
    console.error(`[analyzeConversation] Error analyzing conversation ${conversationId}:`, error);
    return null;
  }
}

/**
 * Gets recent messages from a conversation
 */
async function getRecentMessages(
  conversationId: string,
  limitCount = 50
): Promise<FirebaseFirestore.DocumentData[]> {
  try {
    const messagesSnapshot = await firestore
      .collection(COLLECTION_CONVERSATIONS)
      .doc(conversationId)
      .collection(SUBCOLLECTION_MESSAGES)
      .orderBy("timestamp", "desc")
      .limit(limitCount)
      .get();

    return messagesSnapshot.docs.map(doc => doc.data()).reverse();
  } catch (error) {
    console.error(`[getRecentMessages] Error fetching messages for ${conversationId}:`, error);
    return [];
  }
}

/**
 * Checks if a conversation is active and should be analyzed
 */
function isActiveConversation(conversationData: FirebaseFirestore.DocumentData): boolean {
  const lastMessageTimestamp = conversationData.lastMessageTimestamp;
  if (!lastMessageTimestamp) {
    return false;
  }

  // Consider conversations active if there was activity in the last 7 days
  const lastMessageDate = lastMessageTimestamp.toDate();
  const daysSinceLastMessage = (Date.now() - lastMessageDate.getTime()) / (1000 * 60 * 60 * 24);

  return daysSinceLastMessage <= 7;
}

/**
 * Stores coordination insights in Firestore
 * Exported for testing purposes
 */
export async function storeInsights(
  conversationId: string,
  teamId: string,
  insights: CoordinationInsight
): Promise<void> {
  const timestamp = admin.firestore.Timestamp.now();
  const expiryDate = new Date();
  expiryDate.setDate(expiryDate.getDate() + 7); // Expire after 7 days

  const insightDoc = {
    conversationId,
    teamId,
    insights,
    createdAt: timestamp,
    expiresAt: admin.firestore.Timestamp.fromDate(expiryDate),
    updatedAt: timestamp,
  };

  // Use conversation ID as the document key for deduplication
  await firestore
    .collection("coordinationInsights")
    .doc(conversationId)
    .set(insightDoc, { merge: true });

  console.log(`[storeInsights] Stored insights for conversation ${conversationId}`);
}

// ============================================================================
// Team State Analysis (Main Entry Point)
// ============================================================================

export interface TeamAnalysisResult {
  conversationsAnalyzed: number;
  insightsGenerated: number;
  errors: number;
  timestamp: admin.firestore.Timestamp;
}

/**
 * Analyzes team state by scanning active conversations
 * This is the main entry point called by the scheduled function
 */
export async function analyzeTeamState(): Promise<TeamAnalysisResult> {
  console.log("[analyzeTeamState] Starting team coordination analysis");

  const result: TeamAnalysisResult = {
    conversationsAnalyzed: 0,
    insightsGenerated: 0,
    errors: 0,
    timestamp: admin.firestore.Timestamp.now(),
  };

  try {
    // Get all active conversations
    const conversationsSnapshot = await firestore
      .collection(COLLECTION_CONVERSATIONS)
      .orderBy("lastMessageTimestamp", "desc")
      .limit(100) // Analyze up to 100 most recent conversations
      .get();

    console.log(`[analyzeTeamState] Found ${conversationsSnapshot.docs.length} conversations to evaluate`);

    // Process conversations
    for (const conversationDoc of conversationsSnapshot.docs) {
      const conversationData = conversationDoc.data();
      const conversationId = conversationDoc.id;

      // Skip inactive conversations
      if (!isActiveConversation(conversationData)) {
        continue;
      }

      result.conversationsAnalyzed++;

      try {
        // Get recent messages
        const messages = await getRecentMessages(conversationId);

        if (messages.length < 5) {
          // Skip conversations with very few messages
          continue;
        }

        // Analyze conversation
        const insights = await analyzeConversation(conversationId, messages);

        if (!insights) {
          continue;
        }

        // Only store if there are meaningful insights
        const hasInsights =
          insights.actionItems.length > 0 ||
          insights.staleDacisions.length > 0 ||
          insights.upcomingDeadlines.length > 0 ||
          insights.schedulingConflicts.length > 0 ||
          insights.blockers.length > 0;

        if (hasInsights) {
          // Determine team ID from participants
          const teamId = conversationData.participantIds?.[0] || "default";

          await storeInsights(conversationId, teamId, insights);
          result.insightsGenerated++;
        }
      } catch (error) {
        console.error(`[analyzeTeamState] Error analyzing conversation ${conversationId}:`, error);
        result.errors++;
      }
    }

    console.log("[analyzeTeamState] Analysis complete", result);
    return result;
  } catch (error) {
    console.error("[analyzeTeamState] Fatal error during team analysis:", error);
    throw error;
  }
}

/**
 * Saves analysis result summary to Firestore for monitoring
 */
export async function saveAnalysisSummary(result: TeamAnalysisResult): Promise<void> {
  await firestore
    .collection("coordinationAnalysisSummaries")
    .add(result);

  console.log("[saveAnalysisSummary] Saved analysis summary");
}

// ============================================================================
// Scheduled Function: Proactive Coordinator
// ============================================================================

/**
 * Rate limiting state (in-memory for simplicity)
 * In production, this could be stored in Firestore or Redis
 */
let lastRunTimestamp: number | null = null;
const MIN_RUN_INTERVAL_MS = 55 * 60 * 1000; // 55 minutes minimum between runs

/**
 * Checks if the function should run based on rate limiting
 */
function shouldRun(): boolean {
  if (!lastRunTimestamp) {
    return true;
  }

  const timeSinceLastRun = Date.now() - lastRunTimestamp;
  return timeSinceLastRun >= MIN_RUN_INTERVAL_MS;
}

/**
 * Scheduled Cloud Function: Proactive Coordinator
 * Runs every 60 minutes to analyze team coordination and generate insights
 *
 * Scans conversations for:
 * - Unresolved action items
 * - Stale decisions
 * - Upcoming deadlines
 * - Scheduling conflicts
 * - Blockers
 *
 * Stores insights in Firestore collection `coordinationInsights`
 */
export const proactiveCoordinator = onSchedule(
  "every 60 minutes",
  async (event) => {
    console.log("[proactiveCoordinator] Scheduled run triggered at", event.scheduleTime);

    // Rate limiting guard
    if (!shouldRun()) {
      const timeSinceLastRun = Math.floor((Date.now() - (lastRunTimestamp || 0)) / 1000 / 60);
      console.log(`[proactiveCoordinator] Skipping run - last run was ${timeSinceLastRun} minutes ago`);
      return;
    }

    try {
      // Update rate limiting timestamp
      lastRunTimestamp = Date.now();

      // Run team coordination analysis
      const result = await analyzeTeamState();

      // Save summary for monitoring
      await saveAnalysisSummary(result);

      console.log("[proactiveCoordinator] Successfully completed analysis", {
        conversationsAnalyzed: result.conversationsAnalyzed,
        insightsGenerated: result.insightsGenerated,
        errors: result.errors,
      });

      // Log warnings if there were errors
      if (result.errors > 0) {
        console.warn(`[proactiveCoordinator] Completed with ${result.errors} errors`);
      }
    } catch (error) {
      console.error("[proactiveCoordinator] Fatal error during scheduled run:", error);
      // Reset rate limiting on error to allow retry
      lastRunTimestamp = null;
      throw error;
    }
  }
);
