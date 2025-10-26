import * as admin from "firebase-admin";
import { onCall } from "firebase-functions/v2/https";
import { requireAuth } from "../core/auth";
import { COLLECTION_USERS, COLLECTION_CONVERSATIONS, SUBCOLLECTION_MESSAGES, DELIVERY_SENT } from "../core/constants";

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
    email: "alex.rivera@acme.co",
    avatarUrl: "https://i.pravatar.cc/150?img=1",
  },
  {
    id: "mock-priya",
    displayName: "Priya Patel",
    email: "priya.patel@acme.co",
    avatarUrl: "https://i.pravatar.cc/150?img=5",
  },
  {
    id: "mock-sam",
    displayName: "Sam Carter",
    email: "sam.carter@acme.co",
    avatarUrl: "https://i.pravatar.cc/150?img=12",
  },
  {
    id: "mock-jordan",
    displayName: "Jordan Lee",
    email: "jordan.lee@acme.co",
    avatarUrl: "https://i.pravatar.cc/150?img=8",
  },
];

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
          profilePictureURL: contact.avatarUrl || null,
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
  const lastInteractionByUser = computeLastInteractionByUser(participants, lastMessage.timestamp);

  const conversationData: Record<string, unknown> = {
    participantIds: participants,
    isGroup,
    adminIds: [adminId],
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    lastMessage: lastMessage.text,
    lastMessageTimestamp: admin.firestore.Timestamp.fromDate(lastMessage.timestamp),
    lastSenderId: lastMessage.senderId,
    unreadCount: unreadCounts,
    lastInteractionByUser,
    mockSeeded: true,
  };

  if (groupName) {
    conversationData.groupName = groupName;
  }

  await conversationRef.set(conversationData, { merge: true });

  const messageWrites = orderedMessages.map((message) => {
    const messageId = firestore.collection("_").doc().id;
    const messageRef = conversationRef.collection(SUBCOLLECTION_MESSAGES).doc(messageId);

    // Create readReceipts dict with sender and timestamp
    const readReceipts: Record<string, admin.firestore.Timestamp> = {
      [message.senderId]: admin.firestore.Timestamp.fromDate(message.timestamp),
    };

    return messageRef.set({
      conversationId,
      senderId: message.senderId,
      text: message.text,
      timestamp: admin.firestore.Timestamp.fromDate(message.timestamp),
      deliveryState: DELIVERY_SENT,
      readReceipts,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      // AI metadata fields (null by default, will be populated by triggers)
      priorityScore: null,
      priorityLabel: null,
      priorityRationale: null,
      priorityAnalyzedAt: null,
      schedulingIntent: null,
      intentConfidence: null,
      intentAnalyzedAt: null,
      schedulingKeywords: [],
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
  // Project planning & deadlines
  "We need to finalize the Q1 roadmap by Friday. Can you review the draft?",
  "The client demo is scheduled for March 15th. Are we on track?",
  "I'm blocked on the API integration until the auth service is deployed.",
  "Just pushed the feature branch. Ready for code review when you have time.",
  "Sprint planning tomorrow at 10am PT. I'll share the agenda in advance.",

  // Meeting scheduling
  "Can we schedule a sync call this week? I'm free Tuesday 2-4pm or Thursday morning.",
  "Moving our 1:1 to Wednesday at 3pm - does that work for you?",
  "Quick 15min standup at 9am tomorrow to align on priorities?",
  "I need to reschedule our design review. How's Friday afternoon?",
  "Are you available for a quick call now? Found an issue we should discuss.",

  // Action items & assignments
  "I'll take ownership of the database migration. Target completion: end of week.",
  "Can you handle the documentation updates? Deadline is next Monday.",
  "Assigned you the bug fix for the login flow. Let me know if you need context.",
  "I'll review the PR this afternoon and get you feedback by EOD.",
  "Taking on the performance optimization task. Should be done by Wednesday.",

  // Decisions & follow-ups
  "We decided to go with PostgreSQL for the new service. I'll update the architecture doc.",
  "Following up on last week's discussion about the testing strategy - any thoughts?",
  "Have we made a decision on the deployment approach yet?",
  "Per our call yesterday, I'm moving forward with the React Native approach.",
  "Circling back on the API versioning strategy we discussed. Still planning v2 for May?",

  // Status updates & progress
  "Auth service is deployed to staging. Ready for QA testing.",
  "Finished the user research interviews. Compiling insights now.",
  "Payment integration is 80% complete. Just need to handle edge cases.",
  "Hit a snag with the third-party API. Investigating workarounds.",
  "Dashboard redesign is live in production. Monitoring analytics.",

  // Blockers & dependencies
  "Can't proceed with the frontend work until the API endpoints are ready.",
  "Waiting on legal approval for the terms of service updates.",
  "The staging environment is down. Is anyone else seeing this?",
  "Need access to the analytics dashboard to complete my analysis.",
  "External dependency on the vendor API - they're experiencing an outage.",

  // Team coordination
  "Great work on the launch! Team effort really paid off.",
  "I'll be OOO next week. Alex will cover any urgent items.",
  "Thanks for catching that bug before it hit production!",
  "Let's prioritize the security fixes in this sprint.",
  "Anyone have capacity to help with the data migration?",

  // Availability & scheduling conflicts
  "I'm in back-to-back meetings until 4pm. Can we sync after that?",
  "Heads up: I'll be working East Coast hours this week.",
  "Taking PTO on Friday. Wrapping up my tasks by Thursday EOD.",
  "Double-booked for that time slot. Can we find another time?",
  "Running 10 minutes late to our call. Starting without me is fine.",
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

function computeLastInteractionByUser(
  participants: string[],
  lastMessageTime: Date
): Record<string, admin.firestore.Timestamp> {
  const interactions: Record<string, admin.firestore.Timestamp> = {};
  participants.forEach((participant) => {
    // Simulate different interaction times (within last few hours)
    const hoursAgo = randomInt(0, 6);
    const interactionTime = new Date(lastMessageTime.getTime() - hoursAgo * 60 * 60 * 1000);
    interactions[participant] = admin.firestore.Timestamp.fromDate(interactionTime);
  });
  return interactions;
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

export const deleteCoordinationData = onCall(async (request) => {
  requireAuth(request);
  // Delete both coordination collections
  await Promise.all([
    admin.firestore().recursiveDelete(firestore.collection("coordinationInsights")),
    admin.firestore().recursiveDelete(firestore.collection("coordinationAnalysisSummaries")),
  ]);
  return { status: "success" };
});