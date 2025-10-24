import test from "node:test";
import assert from "node:assert/strict";

type AnalyzeTeamStateFunction = () => Promise<{
  conversationsAnalyzed: number;
  insightsGenerated: number;
  errors: number;
  timestamp: unknown;
}>;

type StoreInsightsFunction = (
  conversationId: string,
  teamId: string,
  insights: Record<string, unknown>
) => Promise<void>;

const modulePath = "../ai/coordination";

/**
 * Loads coordination analysis functions with mocked dependencies
 */
function loadCoordinationAnalysis(options: {
  mockConversations?: Array<Record<string, unknown>>;
  mockMessages?: Record<string, Array<Record<string, unknown>>>;
  mockInsightResponse?: unknown;
  shouldReturnError?: boolean;
}): {
  analyzeTeamState: AnalyzeTeamStateFunction;
  storeInsights: StoreInsightsFunction;
  capturedInsights: Array<Record<string, unknown>>;
  capturedOpenAICalls: Array<{ system: string; prompt: string }>;
} {
  const {
    mockConversations = [],
    mockMessages = {},
    mockInsightResponse,
    shouldReturnError = false,
  } = options;

  const capturedInsights: Array<Record<string, unknown>> = [];
  const capturedOpenAICalls: Array<{ system: string; prompt: string }> = [];

  // Mock Vercel AI SDK
  const mockGenerateObject = async (config: {
    model: unknown;
    system: string;
    prompt: string;
    schema: unknown;
    temperature?: number;
  }) => {
    capturedOpenAICalls.push({
      system: config.system,
      prompt: config.prompt,
    });

    if (shouldReturnError) {
      throw new Error("Mock OpenAI error");
    }

    const defaultResponse = mockInsightResponse || {
      actionItems: [],
      staleDacisions: [],
      upcomingDeadlines: [],
      schedulingConflicts: [],
      blockers: [],
      summary: "All clear",
      overallHealth: "good",
    };

    return { object: defaultResponse };
  };

  // Mock firebase-admin
  const mockTimestamp = {
    now: () => ({
      toDate: () => new Date(),
      seconds: Math.floor(Date.now() / 1000),
      nanoseconds: 0,
    }),
    fromDate: (date: Date) => ({
      toDate: () => date,
      seconds: Math.floor(date.getTime() / 1000),
      nanoseconds: 0,
    }),
  };

  const mockFirestore = {
    collection: (collectionName: string) => ({
      doc: (docId?: string) => ({
        get: async () => ({
          exists: true,
          id: docId || "test-doc",
          data: () => mockConversations.find(c => c.id === docId) || {},
        }),
        set: async (data: Record<string, unknown>) => {
          if (collectionName === "coordinationInsights") {
            capturedInsights.push({ conversationId: docId, ...data });
          }
        },
        collection: (subCollectionName: string) => ({
          orderBy: () => ({
            limit: () => ({
              get: async () => ({
                docs: (mockMessages[docId || ""] || []).map((msg, idx) => ({
                  id: `msg-${idx}`,
                  data: () => msg,
                })),
              }),
            }),
          }),
        }),
      }),
      orderBy: () => ({
        limit: (limitCount: number) => ({
          get: async () => ({
            docs: mockConversations.slice(0, limitCount).map(conv => ({
              id: conv.id || "test-conv",
              data: () => conv,
            })),
          }),
        }),
      }),
      add: async (data: Record<string, unknown>) => {
        return { id: "summary-id" };
      },
    }),
  };

  const mockAdmin = {
    apps: [{ name: "default" }],
    firestore: Object.assign(
      () => mockFirestore as unknown,
      {
        Timestamp: mockTimestamp,
        FieldValue: {
          serverTimestamp: () => ({ _methodName: "FieldValue.serverTimestamp" }),
        },
      }
    ),
    initializeApp: () => ({ name: "default" }),
  };

  // Mock require to inject mocks
  const Module = require("module");
  const originalRequire = Module.prototype.require;
  Module.prototype.require = function (id: string) {
    if (id === "ai") {
      return {
        generateObject: mockGenerateObject,
      };
    }
    if (id === "firebase-admin") {
      return mockAdmin;
    }
    return originalRequire.apply(this, arguments);
  };

  delete require.cache[require.resolve(modulePath)];
  const { analyzeTeamState, storeInsights } = require(modulePath) as {
    analyzeTeamState: AnalyzeTeamStateFunction;
    storeInsights: StoreInsightsFunction;
  };

  // Restore mocks
  Module.prototype.require = originalRequire;

  return {
    analyzeTeamState,
    storeInsights,
    capturedInsights,
    capturedOpenAICalls,
  };
}

// ============================================================================
// Analyzer Heuristics Tests
// ============================================================================

test("analyzeTeamState: detects action items in conversations", async () => {
  const recentDate = new Date();

  const { analyzeTeamState, capturedOpenAICalls, capturedInsights } = loadCoordinationAnalysis({
    mockConversations: [
      {
        id: "conv-1",
        lastMessageTimestamp: { toDate: () => recentDate },
        participantIds: ["user-1", "user-2"],
      },
    ],
    mockMessages: {
      "conv-1": [
        { senderId: "user-1", text: "Can you send me the report by Friday?", timestamp: { toDate: () => recentDate } },
        { senderId: "user-2", text: "Sure, I'll get that to you", timestamp: { toDate: () => recentDate } },
        { senderId: "user-1", text: "Also need to review the budget", timestamp: { toDate: () => recentDate } },
        { senderId: "user-2", text: "I'll add it to my list", timestamp: { toDate: () => recentDate } },
        { senderId: "user-1", text: "Thanks!", timestamp: { toDate: () => recentDate } },
        { senderId: "user-2", text: "No problem", timestamp: { toDate: () => recentDate } },
      ],
    },
    mockInsightResponse: {
      actionItems: [
        { description: "Send report by Friday", assignee: "user-2", deadline: "Friday", status: "unresolved" },
        { description: "Review budget", assignee: "user-2", status: "unresolved" },
      ],
      staleDacisions: [],
      upcomingDeadlines: [
        { description: "Report due", dueDate: "Friday", urgency: "high" },
      ],
      schedulingConflicts: [],
      blockers: [],
      summary: "Two action items pending",
      overallHealth: "attention_needed",
    },
  });

  const result = await analyzeTeamState();

  assert.ok(capturedOpenAICalls.length > 0, "Should call AI analyzer");
  assert.ok(capturedOpenAICalls[0].prompt.includes("send me the report"), "Should include action item text");
  assert.equal(capturedInsights.length, 1, "Should store insights");
  assert.ok(capturedInsights[0].insights, "Insights should be present");
});

test("analyzeTeamState: detects scheduling conflicts", async () => {
  const recentDate = new Date();

  const { analyzeTeamState, capturedInsights } = loadCoordinationAnalysis({
    mockConversations: [
      {
        id: "conv-2",
        lastMessageTimestamp: { toDate: () => recentDate },
        participantIds: ["user-1", "user-2", "user-3"],
      },
    ],
    mockMessages: {
      "conv-2": [
        { senderId: "user-1", text: "Let's meet Tuesday at 2pm", timestamp: { toDate: () => recentDate } },
        { senderId: "user-2", text: "I'm booked then, how about 3pm?", timestamp: { toDate: () => recentDate } },
        { senderId: "user-3", text: "I can't do Tuesday at all", timestamp: { toDate: () => recentDate } },
        { senderId: "user-1", text: "This is getting complicated", timestamp: { toDate: () => recentDate } },
        { senderId: "user-2", text: "Maybe Wednesday?", timestamp: { toDate: () => recentDate } },
        { senderId: "user-3", text: "Wednesday works for me", timestamp: { toDate: () => recentDate } },
      ],
    },
    mockInsightResponse: {
      actionItems: [
        { description: "Find meeting time", status: "unresolved" },
      ],
      staleDacisions: [],
      upcomingDeadlines: [],
      schedulingConflicts: [
        { description: "Tuesday 2pm conflict", participants: ["user-1", "user-2", "user-3"] },
      ],
      blockers: [],
      summary: "Scheduling conflict needs resolution",
      overallHealth: "attention_needed",
    },
  });

  const result = await analyzeTeamState();

  assert.equal(result.insightsGenerated, 1, "Should generate insight for scheduling conflict");
  assert.equal(capturedInsights.length, 1, "Should store conflict insight");
});

test("analyzeTeamState: detects blockers", async () => {
  const recentDate = new Date();

  const { analyzeTeamState, capturedOpenAICalls } = loadCoordinationAnalysis({
    mockConversations: [
      {
        id: "conv-3",
        lastMessageTimestamp: { toDate: () => recentDate },
        participantIds: ["user-1", "user-2"],
      },
    ],
    mockMessages: {
      "conv-3": [
        { senderId: "user-1", text: "Can't proceed until we get API access", timestamp: { toDate: () => recentDate } },
        { senderId: "user-2", text: "I emailed IT but no response yet", timestamp: { toDate: () => recentDate } },
        { senderId: "user-1", text: "This is blocking the whole project", timestamp: { toDate: () => recentDate } },
        { senderId: "user-2", text: "I'll follow up again", timestamp: { toDate: () => recentDate } },
        { senderId: "user-1", text: "Thanks, we're stuck without it", timestamp: { toDate: () => recentDate } },
      ],
    },
    mockInsightResponse: {
      actionItems: [
        { description: "Follow up with IT", assignee: "user-2", status: "unresolved" },
      ],
      staleDacisions: [],
      upcomingDeadlines: [],
      schedulingConflicts: [],
      blockers: [
        { description: "Waiting for API access from IT", blockedBy: "IT department" },
      ],
      summary: "Project blocked on API access",
      overallHealth: "critical",
    },
  });

  const result = await analyzeTeamState();

  assert.ok(capturedOpenAICalls[0].prompt.includes("blocking"), "Should detect blocker language");
  assert.equal(result.insightsGenerated, 1, "Should generate blocker insight");
});

test("analyzeTeamState: detects stale decisions", async () => {
  const oldDate = new Date();
  oldDate.setDate(oldDate.getDate() - 3); // 3 days ago
  const recentDate = new Date();

  const { analyzeTeamState, capturedInsights } = loadCoordinationAnalysis({
    mockConversations: [
      {
        id: "conv-4",
        lastMessageTimestamp: { toDate: () => recentDate },
        participantIds: ["user-1", "user-2"],
      },
    ],
    mockMessages: {
      "conv-4": [
        { senderId: "user-1", text: "We decided to use React for the frontend", timestamp: { toDate: () => oldDate } },
        { senderId: "user-2", text: "Sounds good", timestamp: { toDate: () => oldDate } },
        { senderId: "user-1", text: "So when do we start?", timestamp: { toDate: () => recentDate } },
        { senderId: "user-2", text: "Not sure, waiting on something", timestamp: { toDate: () => recentDate } },
        { senderId: "user-1", text: "It's been a while", timestamp: { toDate: () => recentDate } },
      ],
    },
    mockInsightResponse: {
      actionItems: [],
      staleDacisions: [
        { topic: "React frontend implementation", lastMentioned: "3 days ago", reason: "No follow-up action taken" },
      ],
      upcomingDeadlines: [],
      schedulingConflicts: [],
      blockers: [],
      summary: "Decision needs follow-up",
      overallHealth: "attention_needed",
    },
  });

  const result = await analyzeTeamState();

  assert.equal(result.insightsGenerated, 1, "Should detect stale decision");
  assert.equal(capturedInsights.length, 1, "Should store stale decision insight");
});

// ============================================================================
// Firestore Persistence Tests
// ============================================================================

test("storeInsights: includes expiry timestamp", async () => {
  const { storeInsights, capturedInsights } = loadCoordinationAnalysis({});

  const testInsights = {
    actionItems: [{ description: "Test action", status: "unresolved" }],
    staleDacisions: [],
    upcomingDeadlines: [],
    schedulingConflicts: [],
    blockers: [],
    summary: "Test summary",
    overallHealth: "good",
  };

  await storeInsights("conv-test", "team-1", testInsights);

  assert.equal(capturedInsights.length, 1, "Should store insights");
  assert.ok(capturedInsights[0].expiresAt, "Should include expiry timestamp");
  assert.ok(capturedInsights[0].createdAt, "Should include creation timestamp");
});

test("storeInsights: uses conversationId as dedupe key", async () => {
  const { storeInsights, capturedInsights } = loadCoordinationAnalysis({});

  const testInsights = {
    actionItems: [],
    staleDacisions: [],
    upcomingDeadlines: [],
    schedulingConflicts: [],
    blockers: [],
    summary: "Test",
    overallHealth: "good",
  };

  // Store same conversation twice
  await storeInsights("conv-dedupe", "team-1", testInsights);
  await storeInsights("conv-dedupe", "team-1", testInsights);

  // Both should use same document ID (conversationId as key)
  assert.equal(capturedInsights[0].conversationId, "conv-dedupe");
  assert.equal(capturedInsights[1].conversationId, "conv-dedupe");
});

test("storeInsights: includes teamId in document", async () => {
  const { storeInsights, capturedInsights } = loadCoordinationAnalysis({});

  const testInsights = {
    actionItems: [],
    staleDacisions: [],
    upcomingDeadlines: [],
    schedulingConflicts: [],
    blockers: [],
    summary: "Test",
    overallHealth: "good",
  };

  await storeInsights("conv-team-test", "team-alpha", testInsights);

  assert.equal(capturedInsights.length, 1);
  assert.equal(capturedInsights[0].teamId, "team-alpha", "Should include teamId");
  assert.equal(capturedInsights[0].conversationId, "conv-team-test");
});
