import test from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import * as https from "firebase-functions/v2/https";

type SuggestMeetingTimesHandler = (request: Record<string, unknown>) => Promise<unknown>;

const modulePath = "../index";

interface MockMessage {
  senderId: string;
  text: string;
  timestamp: { toDate: () => Date };
}

function loadSuggestMeetingTimes(options: {
  conversationExists?: boolean;
  userIsParticipant?: boolean;
  mockMessages?: MockMessage[];
  mockOpenAIResponse?: unknown;
}): {
  suggestMeetingTimes: SuggestMeetingTimesHandler;
  capturedOpenAICalls: Array<{ system: string; prompt: string }>;
  capturedAnalytics: {
    summaryWrites: Array<Record<string, unknown>>;
    requestDetails: Array<Record<string, unknown>>;
  };
} {
  const {
    conversationExists = true,
    userIsParticipant = true,
    mockMessages = [],
    mockOpenAIResponse = {
      suggestions: [
        {
          startTime: "2025-10-25T14:00:00Z",
          endTime: "2025-10-25T15:00:00Z",
          score: 0.9,
          justification: "Peak activity time based on historical patterns",
          dayOfWeek: "Friday",
          timeOfDay: "afternoon",
        },
        {
          startTime: "2025-10-26T10:00:00Z",
          endTime: "2025-10-26T11:00:00Z",
          score: 0.8,
          justification: "Morning slot with good availability",
          dayOfWeek: "Saturday",
          timeOfDay: "morning",
        },
        {
          startTime: "2025-10-27T16:00:00Z",
          endTime: "2025-10-27T17:00:00Z",
          score: 0.7,
          justification: "Alternative afternoon option",
          dayOfWeek: "Sunday",
          timeOfDay: "afternoon",
        },
      ],
    },
  } = options;

  const capturedOpenAICalls: Array<{ system: string; prompt: string }> = [];
  const capturedAnalytics = {
    summaryWrites: [] as Array<Record<string, unknown>>,
    requestDetails: [] as Array<Record<string, unknown>>,
  };

  // Mock Firestore
  const firestoreStub = {
    collection: (collectionName: string) => {
      if (collectionName === "analytics") {
        return {
          doc: (docId: string) => {
            if (docId === "meetingSuggestions") {
              return {
                set: async (data: Record<string, unknown>, options?: { merge: boolean }) => {
                  capturedAnalytics.summaryWrites.push(data);
                  return {};
                },
                collection: (subCollectionName: string) => {
                  if (subCollectionName === "requests") {
                    return {
                      add: async (data: Record<string, unknown>) => {
                        capturedAnalytics.requestDetails.push(data);
                        return { id: "request-123" };
                      },
                    };
                  }
                  return {};
                },
              };
            }
            return {
              set: async () => ({}),
              collection: () => ({ add: async () => ({ id: "unknown" }) }),
            };
          },
        };
      } else if (collectionName === "conversations") {
        return {
          doc: (conversationId: string) => ({
            get: async () => ({
              exists: conversationExists,
              data: () =>
                conversationExists
                  ? {
                      participantIds: userIsParticipant
                        ? ["user-123", "user-456", "user-789"]
                        : ["user-456", "user-789"],
                    }
                  : undefined,
              id: conversationId,
            }),
            collection: (subCollectionName: string) => {
              if (subCollectionName === "messages") {
                return {
                  where: () => ({
                    orderBy: () => ({
                      limit: () => ({
                        get: async () => ({
                          docs: mockMessages.map((msg, idx) => ({
                            id: `msg-${idx}`,
                            data: () => msg,
                          })),
                        }),
                      }),
                    }),
                  }),
                };
              }
              return {};
            },
          }),
          where: () => ({
            limit: () => ({
              get: async () => ({
                docs: conversationExists
                  ? [
                      {
                        id: "conv-1",
                      },
                    ]
                  : [],
              }),
            }),
          }),
        };
      } else if (collectionName === "users") {
        return {
          doc: (userId: string) => ({
            get: async () => ({
              exists: true,
              data: () => ({
                displayName: `User ${userId}`,
              }),
            }),
          }),
        };
      } else if (collectionName === "bots") {
        return {
          doc: () => ({
            get: async () => ({
              exists: false,
            }),
          }),
        };
      }
      return {};
    },
  };

  // Mock Firebase Admin
  const adminAny = admin as unknown as Record<string, unknown>;
  const originalInitializeAppDescriptor = Object.getOwnPropertyDescriptor(adminAny, "initializeApp");
  const originalFirestoreDescriptor = Object.getOwnPropertyDescriptor(adminAny, "firestore");

  Object.defineProperty(adminAny, "initializeApp", {
    configurable: true,
    writable: true,
    value: () => ({ name: "test-app" }),
  });

  Object.defineProperty(adminAny, "firestore", {
    configurable: true,
    writable: true,
    value: () => firestoreStub,
  });

  // Mock https.onCall
  delete require.cache[require.resolve(modulePath)];
  const httpsAny = https as unknown as Record<string, unknown>;
  const originalOnCall = httpsAny.onCall;

  Object.defineProperty(httpsAny, "onCall", {
    configurable: true,
    writable: true,
    value: (handler: SuggestMeetingTimesHandler) => handler,
  });

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
    return { object: mockOpenAIResponse };
  };

  const mockTool = (config: unknown) => {
    // Mock tool function that just returns the config
    return config;
  };

  const mockExperimentalAgent = class {
    constructor() {}
    generate() {
      return Promise.resolve({
        text: "Mock response",
        usage: { totalTokens: 100 },
      });
    }
  };

  // We need to mock the ai module before requiring index
  const Module = require("module");
  const originalRequire = Module.prototype.require;
  Module.prototype.require = function (id: string) {
    if (id === "ai") {
      return {
        generateObject: mockGenerateObject,
        tool: mockTool,
        Experimental_Agent: mockExperimentalAgent,
      };
    }
    return originalRequire.apply(this, arguments);
  };

  const { suggestMeetingTimes } = require(modulePath) as {
    suggestMeetingTimes: SuggestMeetingTimesHandler;
  };

  // Restore mocks
  Module.prototype.require = originalRequire;

  if (originalInitializeAppDescriptor) {
    Object.defineProperty(adminAny, "initializeApp", originalInitializeAppDescriptor);
  } else {
    delete adminAny.initializeApp;
  }

  if (originalFirestoreDescriptor) {
    Object.defineProperty(adminAny, "firestore", originalFirestoreDescriptor);
  } else {
    delete adminAny.firestore;
  }

  if (originalOnCall) {
    Object.defineProperty(httpsAny, "onCall", {
      configurable: true,
      writable: true,
      value: originalOnCall,
    });
  } else {
    delete httpsAny.onCall;
  }

  return {
    suggestMeetingTimes,
    capturedOpenAICalls,
    capturedAnalytics,
  };
}

test("suggestMeetingTimes rejects unauthenticated requests", async () => {
  const { suggestMeetingTimes } = loadSuggestMeetingTimes({});

  const unauthenticatedContext = {
    auth: undefined,
    data: {
      conversationId: "conv-123",
      participantIds: ["user-456"],
      durationMinutes: 60,
    },
  };

  await assert.rejects(
    async () => {
      await suggestMeetingTimes(unauthenticatedContext);
    },
    (error: unknown) => {
      assert.ok(error instanceof https.HttpsError);
      assert.equal((error as https.HttpsError).code, "unauthenticated");
      return true;
    }
  );
});

test("suggestMeetingTimes rejects when conversationId is missing", async () => {
  const { suggestMeetingTimes } = loadSuggestMeetingTimes({});

  const request = {
    auth: { uid: "user-123" },
    data: {
      participantIds: ["user-456"],
      durationMinutes: 60,
    },
  };

  await assert.rejects(
    async () => {
      await suggestMeetingTimes(request);
    },
    (error: unknown) => {
      assert.ok(error instanceof https.HttpsError);
      assert.equal((error as https.HttpsError).code, "invalid-argument");
      assert.ok((error as https.HttpsError).message.includes("conversationId"));
      return true;
    }
  );
});

test("suggestMeetingTimes rejects when participantIds is missing", async () => {
  const { suggestMeetingTimes } = loadSuggestMeetingTimes({});

  const request = {
    auth: { uid: "user-123" },
    data: {
      conversationId: "conv-123",
      durationMinutes: 60,
    },
  };

  await assert.rejects(
    async () => {
      await suggestMeetingTimes(request);
    },
    (error: unknown) => {
      assert.ok(error instanceof https.HttpsError);
      assert.equal((error as https.HttpsError).code, "invalid-argument");
      assert.ok((error as https.HttpsError).message.includes("participantIds"));
      return true;
    }
  );
});

test("suggestMeetingTimes rejects when durationMinutes is invalid", async () => {
  const { suggestMeetingTimes } = loadSuggestMeetingTimes({});

  const request = {
    auth: { uid: "user-123" },
    data: {
      conversationId: "conv-123",
      participantIds: ["user-456"],
      durationMinutes: 0,
    },
  };

  await assert.rejects(
    async () => {
      await suggestMeetingTimes(request);
    },
    (error: unknown) => {
      assert.ok(error instanceof https.HttpsError);
      assert.equal((error as https.HttpsError).code, "invalid-argument");
      assert.ok((error as https.HttpsError).message.includes("durationMinutes"));
      return true;
    }
  );
});

test("suggestMeetingTimes rejects when conversation not found", async () => {
  const { suggestMeetingTimes } = loadSuggestMeetingTimes({
    conversationExists: false,
  });

  const request = {
    auth: { uid: "user-123" },
    data: {
      conversationId: "conv-123",
      participantIds: ["user-456"],
      durationMinutes: 60,
    },
  };

  await assert.rejects(
    async () => {
      await suggestMeetingTimes(request);
    },
    (error: unknown) => {
      assert.ok(error instanceof https.HttpsError);
      assert.equal((error as https.HttpsError).code, "not-found");
      return true;
    }
  );
});

test("suggestMeetingTimes rejects when user is not a participant", async () => {
  const { suggestMeetingTimes } = loadSuggestMeetingTimes({
    userIsParticipant: false,
  });

  const request = {
    auth: { uid: "user-123" },
    data: {
      conversationId: "conv-123",
      participantIds: ["user-456"],
      durationMinutes: 60,
    },
  };

  await assert.rejects(
    async () => {
      await suggestMeetingTimes(request);
    },
    (error: unknown) => {
      assert.ok(error instanceof https.HttpsError);
      assert.equal((error as https.HttpsError).code, "permission-denied");
      return true;
    }
  );
});

test("suggestMeetingTimes returns suggestions with correct structure", async () => {
  const mockMessages: MockMessage[] = [
    {
      senderId: "user-456",
      text: "Let's schedule a meeting",
      timestamp: {
        toDate: () => new Date("2025-10-20T14:30:00Z"),
      },
    },
    {
      senderId: "user-789",
      text: "Sure, sounds good",
      timestamp: {
        toDate: () => new Date("2025-10-20T15:00:00Z"),
      },
    },
  ];

  const { suggestMeetingTimes, capturedOpenAICalls } = loadSuggestMeetingTimes({
    mockMessages,
  });

  const request = {
    auth: { uid: "user-123" },
    data: {
      conversationId: "conv-123",
      participantIds: ["user-456", "user-789"],
      durationMinutes: 60,
    },
  };

  const response = (await suggestMeetingTimes(request)) as {
    suggestions: Array<{
      startTime: string;
      endTime: string;
      score: number;
      justification: string;
      dayOfWeek: string;
      timeOfDay: string;
    }>;
    conversation_id: string;
    duration_minutes: number;
    participant_count: number;
    generated_at: string;
    expires_at: string;
  };

  // Verify response structure
  assert.ok(response.suggestions);
  assert.ok(Array.isArray(response.suggestions));
  assert.equal(response.suggestions.length, 3);
  assert.equal(response.conversation_id, "conv-123");
  assert.equal(response.duration_minutes, 60);
  assert.equal(response.participant_count, 2);
  assert.ok(response.generated_at);
  assert.ok(response.expires_at);

  // Verify suggestions are sorted by score (descending)
  assert.ok(response.suggestions[0].score >= response.suggestions[1].score);
  assert.ok(response.suggestions[1].score >= response.suggestions[2].score);

  // Verify first suggestion structure
  const firstSuggestion = response.suggestions[0];
  assert.equal(firstSuggestion.startTime, "2025-10-25T14:00:00Z");
  assert.equal(firstSuggestion.endTime, "2025-10-25T15:00:00Z");
  assert.equal(firstSuggestion.score, 0.9);
  assert.ok(firstSuggestion.justification);
  assert.equal(firstSuggestion.dayOfWeek, "Friday");
  assert.equal(firstSuggestion.timeOfDay, "afternoon");

  // Verify OpenAI was called
  assert.equal(capturedOpenAICalls.length, 1);
  const openAICall = capturedOpenAICalls[0];
  assert.ok(openAICall.system.includes("meeting scheduling assistant"));
  assert.ok(openAICall.prompt.includes("60-minute meeting"));
});

test("suggestMeetingTimes includes activity analysis in OpenAI prompt", async () => {
  const { suggestMeetingTimes, capturedOpenAICalls } = loadSuggestMeetingTimes({});

  const request = {
    auth: { uid: "user-123" },
    data: {
      conversationId: "conv-123",
      participantIds: ["user-456"],
      durationMinutes: 30,
      preferredDays: 7,
    },
  };

  await suggestMeetingTimes(request);

  assert.equal(capturedOpenAICalls.length, 1);
  const openAICall = capturedOpenAICalls[0];

  // Verify prompt includes key context
  assert.ok(openAICall.prompt.includes("30-minute meeting"));
  assert.ok(openAICall.prompt.includes("Activity Analysis"));
  assert.ok(openAICall.system.includes("Next 7 days"));
});

// MARK: - Analytics Tests

test("suggestMeetingTimes records analytics for successful requests", async () => {
  const { suggestMeetingTimes, capturedAnalytics } = loadSuggestMeetingTimes({});

  const request = {
    auth: { uid: "user-123" },
    data: {
      conversationId: "conv-123",
      participantIds: ["user-456", "user-789"],
      durationMinutes: 60,
    },
  };

  await suggestMeetingTimes(request);

  // Verify summary analytics were written
  assert.equal(capturedAnalytics.summaryWrites.length, 1);
  const summaryWrite = capturedAnalytics.summaryWrites[0];

  // Check that counters are being incremented
  assert.ok(summaryWrite.totalRequests);
  assert.ok(summaryWrite.totalSuggestionsGenerated);
  assert.ok(summaryWrite.lastRequestAt);
  assert.ok(summaryWrite.averageParticipantCount);
  assert.ok(summaryWrite.averageDurationMinutes);

  // Verify individual request details were recorded
  assert.equal(capturedAnalytics.requestDetails.length, 1);
  const requestDetail = capturedAnalytics.requestDetails[0];

  assert.equal(requestDetail.conversationId, "conv-123");
  assert.equal(requestDetail.participantCount, 2);
  assert.equal(requestDetail.durationMinutes, 60);
  assert.equal(requestDetail.suggestionsCount, 3); // Default mock has 3 suggestions
  assert.equal(requestDetail.topSuggestionScore, 0.9); // Highest score from mock
  assert.equal(requestDetail.requestedBy, "user-123");
  assert.ok(requestDetail.timestamp);
});

test("suggestMeetingTimes analytics includes correct suggestion counts", async () => {
  const customMockResponse = {
    suggestions: [
      {
        startTime: "2025-10-25T14:00:00Z",
        endTime: "2025-10-25T15:00:00Z",
        score: 0.95,
        justification: "Best time",
        dayOfWeek: "Friday",
        timeOfDay: "afternoon",
      },
      {
        startTime: "2025-10-26T10:00:00Z",
        endTime: "2025-10-26T11:00:00Z",
        score: 0.85,
        justification: "Good alternative",
        dayOfWeek: "Saturday",
        timeOfDay: "morning",
      },
      {
        startTime: "2025-10-27T16:00:00Z",
        endTime: "2025-10-27T17:00:00Z",
        score: 0.75,
        justification: "Another option",
        dayOfWeek: "Sunday",
        timeOfDay: "afternoon",
      },
      {
        startTime: "2025-10-28T14:00:00Z",
        endTime: "2025-10-28T15:00:00Z",
        score: 0.70,
        justification: "Fourth option",
        dayOfWeek: "Monday",
        timeOfDay: "afternoon",
      },
    ],
  };

  const { suggestMeetingTimes, capturedAnalytics } = loadSuggestMeetingTimes({
    mockOpenAIResponse: customMockResponse,
  });

  const request = {
    auth: { uid: "user-123" },
    data: {
      conversationId: "conv-test",
      participantIds: ["user-456"],
      durationMinutes: 30,
    },
  };

  await suggestMeetingTimes(request);

  const requestDetail = capturedAnalytics.requestDetails[0];
  assert.equal(requestDetail.suggestionsCount, 4);
  assert.equal(requestDetail.topSuggestionScore, 0.95);
});

test("suggestMeetingTimes analytics tracks participant count correctly", async () => {
  const { suggestMeetingTimes, capturedAnalytics } = loadSuggestMeetingTimes({});

  const request = {
    auth: { uid: "user-123" },
    data: {
      conversationId: "conv-456",
      participantIds: ["user-1", "user-2", "user-3", "user-4", "user-5"],
      durationMinutes: 45,
    },
  };

  await suggestMeetingTimes(request);

  const requestDetail = capturedAnalytics.requestDetails[0];
  assert.equal(requestDetail.participantCount, 5);
  assert.equal(requestDetail.durationMinutes, 45);
});

test("suggestMeetingTimes analytics handles single participant", async () => {
  const { suggestMeetingTimes, capturedAnalytics } = loadSuggestMeetingTimes({});

  const request = {
    auth: { uid: "user-123" },
    data: {
      conversationId: "conv-789",
      participantIds: ["user-456"],
      durationMinutes: 15,
    },
  };

  await suggestMeetingTimes(request);

  const requestDetail = capturedAnalytics.requestDetails[0];
  assert.equal(requestDetail.participantCount, 1);
  assert.equal(requestDetail.durationMinutes, 15);
});

test("suggestMeetingTimes records timestamps in analytics", async () => {
  const { suggestMeetingTimes, capturedAnalytics } = loadSuggestMeetingTimes({});

  const request = {
    auth: { uid: "user-123" },
    data: {
      conversationId: "conv-timestamp",
      participantIds: ["user-456"],
      durationMinutes: 60,
    },
  };

  await suggestMeetingTimes(request);

  // Verify timestamp fields are present
  const summaryWrite = capturedAnalytics.summaryWrites[0];
  assert.ok(summaryWrite.lastRequestAt, "Summary should have lastRequestAt");

  const requestDetail = capturedAnalytics.requestDetails[0];
  assert.ok(requestDetail.timestamp, "Request detail should have timestamp");
});
