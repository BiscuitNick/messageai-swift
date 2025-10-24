import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { generateObject } from "ai";
import { openai } from "../core/config";
import { z } from "zod";

import { requireAuth } from "../core/auth";

const firestore = admin.firestore();
import { COLLECTION_CONVERSATIONS, COLLECTION_USERS, COLLECTION_BOTS } from "../core/constants";


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
        .collection("messages")
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

    const systemPrompt = `You are a meeting scheduling assistant that suggests optimal meeting times based on participant activity patterns.\n\nYour task is to suggest 3-5 meeting time slots that maximize the likelihood of participant availability.\n\nConsider:\n1. Historical activity patterns (when participants are typically active)\n2. Standard business hours and timezone considerations\n3. Avoiding early mornings, late evenings, and weekends unless activity suggests otherwise\n4. Meeting duration requirements\n5. Providing a mix of options (different days/times)\n\nFor each suggestion:\n- Provide exact start and end times as ISO 8601 timestamps\n- Score the suggestion (0-1) based on how well it matches activity patterns\n- Justify why this time works well\n- Identify the day of week and general time of day\n\nCurrent date: ${now.toISOString()}\nSuggestion window: Next ${preferredDays} days (until ${endDate.toISOString()})`;

    const userPrompt = `Suggest ${durationMinutes}-minute meeting times for these participants:\n\n${participantContext}\n\nActivity Analysis:\n- Most active hours (UTC): ${topHours.join(", ")}\n- Most active days: ${topDays.join(", ")}\n- Estimated timezone offset: ${activityAnalysis.activeTimezoneOffset} minutes from UTC\n\nGenerate 3-5 ranked meeting time suggestions within the next ${preferredDays} days.`;

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

    return { suggestions };

  } catch (error) {
    console.error("Meeting suggestion error:", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", "Failed to suggest meeting times", error);
  }
});

import { fetchSenderNames } from "../core/utils";
