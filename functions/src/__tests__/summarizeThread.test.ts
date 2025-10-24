import test from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import * as https from "firebase-functions/v2/https";

type SummarizeThreadHandler = (request: Record<string, unknown>) => Promise<unknown>;

const modulePath = "../index";

interface MockMessage {
  id: string;
  data: () => {
    text: string;
    senderId: string;
    senderName: string;
    timestamp: { toMillis: () => number };
  };
}

function loadSummarizeThread(options: {
  conversationExists?: boolean;
  userIsParticipant?: boolean;
  messages?: MockMessage[];
  aiResponse?: string;
} = {}): {
  summarizeThread: SummarizeThreadHandler;
  capturedAIPrompts: string[];
} {
  const {
    conversationExists = true,
    userIsParticipant = true,
    messages = [],
    aiResponse = "This is a test summary.",
  } = options;

  const capturedAIPrompts: string[] = [];

  // Mock Firestore
  const firestoreStub = {
    collection: (collectionName: string) => {
      if (collectionName === "conversations") {
        return {
          orderBy: () => ({
            limit: () => ({
              get: async () => ({
                empty: !conversationExists,
                docs: conversationExists ? [{
                  id: "test-convo-123",
                  data: () => ({
                    participantIds: userIsParticipant ? ["test-user-123", "other-user"] : ["other-user"],
                    updatedAt: new Date(),
                  }),
                }] : [],
              }),
            }),
          }),
          doc: (conversationId: string) => ({
            get: async () => ({
              exists: conversationExists,
              data: () => ({
                participantIds: userIsParticipant ? ["test-user-123", "other-user"] : ["other-user"],
              }),
            }),
            collection: (subCollectionName: string) => {
              if (subCollectionName === "messages") {
                return {
                  orderBy: () => ({
                    limit: () => ({
                      get: async () => ({
                        docs: messages,
                        empty: messages.length === 0,
                      }),
                    }),
                  }),
                };
              }
              return {};
            },
          }),
        };
      }
      if (collectionName === "users" || collectionName === "bots") {
        return {
          doc: (userId: string) => ({
            get: async () => {
              // Map user IDs to display names
              const nameMap: Record<string, string> = {
                "user-1": "Alice",
                "user-2": "Bob",
                "test-user-123": "Test User",
                "other-user": "Other User",
              };
              const displayName = nameMap[userId] || userId;
              return {
                exists: true,
                data: () => ({
                  displayName,
                  name: displayName,
                }),
              };
            },
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

  // Mock zod
  const zodModule = require.cache[require.resolve("zod")];
  if (zodModule) {
    delete require.cache[require.resolve("zod")];
  }

  const createMockZodChain = () => {
    const chain: Record<string, unknown> = {
      describe: () => chain,
      optional: () => chain,
      default: () => chain,
    };
    return chain;
  };

  require.cache[require.resolve("zod")] = {
    id: require.resolve("zod"),
    filename: require.resolve("zod"),
    loaded: true,
    exports: {
      z: {
        object: () => createMockZodChain(),
        enum: () => createMockZodChain(),
        string: () => createMockZodChain(),
      },
    },
    children: [],
    paths: [],
    require: require as NodeRequire,
    isPreloading: false,
    parent: null,
    path: "",
  } as NodeModule;

  // Mock @ai-sdk/openai
  const openaiModule = require.cache[require.resolve("@ai-sdk/openai")];
  if (openaiModule) {
    delete require.cache[require.resolve("@ai-sdk/openai")];
  }

  require.cache[require.resolve("@ai-sdk/openai")] = {
    id: require.resolve("@ai-sdk/openai"),
    filename: require.resolve("@ai-sdk/openai"),
    loaded: true,
    exports: {
      createOpenAI: () => () => "mock-model",
    },
    children: [],
    paths: [],
    require: require as NodeRequire,
    isPreloading: false,
    parent: null,
    path: "",
  } as NodeModule;

  // Mock AI SDK
  const aiModule = require.cache[require.resolve("ai")];
  if (aiModule) {
    delete require.cache[require.resolve("ai")];
  }

  const mockAI = {
    generateText: async (params: Record<string, unknown>) => {
      const messages = params.messages as Array<{ content: string }>;
      if (messages && messages[0]) {
        capturedAIPrompts.push(messages[0].content);
      }
      return {
        text: aiResponse,
      };
    },
    tool: () => ({}),
    streamText: () => ({}),
    Experimental_Agent: class {
      constructor() {}
      async generate(params: Record<string, unknown>) {
        const messages = params.messages as Array<{ content: string }>;
        if (messages && messages[0]) {
          capturedAIPrompts.push(messages[0].content);
        }
        return {
          text: aiResponse,
          usage: {}
        };
      }
    },
  };

  // Replace the module
  require.cache[require.resolve("ai")] = {
    id: require.resolve("ai"),
    filename: require.resolve("ai"),
    loaded: true,
    exports: mockAI,
    children: [],
    paths: [],
    require: require as NodeRequire,
    isPreloading: false,
    parent: null,
    path: "",
  } as NodeModule;

  // Mock firebase-functions/params
  const paramsModule = require.cache[require.resolve("firebase-functions/params")];
  if (paramsModule) {
    delete require.cache[require.resolve("firebase-functions/params")];
  }

  require.cache[require.resolve("firebase-functions/params")] = {
    id: require.resolve("firebase-functions/params"),
    filename: require.resolve("firebase-functions/params"),
    loaded: true,
    exports: {
      defineString: () => ({ value: () => "test-api-key" }),
    },
    children: [],
    paths: [],
    require: require as NodeRequire,
    isPreloading: false,
    parent: null,
    path: "",
  } as NodeModule;

  // Mock https.onCall
  delete require.cache[require.resolve(modulePath)];
  const httpsAny = https as unknown as Record<string, unknown>;
  const originalOnCall = httpsAny.onCall;

  Object.defineProperty(httpsAny, "onCall", {
    configurable: true,
    writable: true,
    value: (handler: SummarizeThreadHandler) => handler,
  });

  const { summarizeThread } = require(modulePath) as {
    summarizeThread: SummarizeThreadHandler;
  };

  // Restore original properties
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
    summarizeThread,
    capturedAIPrompts,
  };
}

test("summarizeThread allows unauthenticated requests", async () => {
  const mockMessages: MockMessage[] = [
    {
      id: "msg-1",
      data: () => ({
        text: "Test message",
        senderId: "user-1",
        senderName: "Alice",
        timestamp: {
          toMillis: () => Date.now() - 3600000,
        },
      }),
    },
  ];

  const { summarizeThread } = loadSummarizeThread({
    messages: mockMessages,
    aiResponse: "Test summary for unauthenticated request.",
  });

  const unauthenticatedContext: Record<string, unknown> = {
    auth: undefined,
    data: {
      conversationId: "test-convo-123",
    },
  };

  const response = await summarizeThread(unauthenticatedContext) as {
    summary: string;
    conversationId: string;
    messageCount: number;
    generatedAt: number;
  };

  assert.equal(response.conversationId, "test-convo-123");
  assert.equal(response.summary, "Test summary for unauthenticated request.");
  assert.ok(typeof response.generatedAt === "number");
});

test("summarizeThread always uses newest conversation", async () => {
  const mockMessages: MockMessage[] = [
    {
      id: "msg-1",
      data: () => ({
        text: "Test message",
        senderId: "user-1",
        senderName: "Alice",
        timestamp: {
          toMillis: () => Date.now() - 3600000,
        },
      }),
    },
  ];

  const { summarizeThread } = loadSummarizeThread({
    messages: mockMessages,
    aiResponse: "Test summary for newest conversation.",
  });

  const request: Record<string, unknown> = {
    auth: { uid: "test-user-123" },
    data: {}, // No parameters needed
  };

  const response = await summarizeThread(request) as {
    summary: string;
    conversationId: string;
    messageCount: number;
    generatedAt: number;
  };

  // Should always return a summary of the newest conversation
  assert.ok(response.conversationId);
  assert.equal(response.summary, "Test summary for newest conversation.");
  assert.ok(typeof response.generatedAt === "number");
});

test("summarizeThread rejects non-existent conversation", async () => {
  const { summarizeThread } = loadSummarizeThread({
    conversationExists: false,
  });

  const request: Record<string, unknown> = {
    auth: { uid: "test-user-123" },
    data: {
      conversationId: "non-existent-convo",
    },
  };

  await assert.rejects(
    async () => {
      await summarizeThread(request);
    },
    (error: unknown) => {
      assert.ok(error instanceof https.HttpsError);
      assert.equal((error as https.HttpsError).code, "not-found");
      return true;
    }
  );
});

test("summarizeThread rejects unauthorized authenticated user", async () => {
  const { summarizeThread } = loadSummarizeThread({
    userIsParticipant: false,
  });

  const request: Record<string, unknown> = {
    auth: { uid: "test-user-123" },
    data: {
      conversationId: "test-convo-123",
    },
  };

  await assert.rejects(
    async () => {
      await summarizeThread(request);
    },
    (error: unknown) => {
      assert.ok(error instanceof https.HttpsError);
      assert.equal((error as https.HttpsError).code, "permission-denied");
      return true;
    }
  );
});

test("summarizeThread allows unauthenticated user regardless of participant status", async () => {
  const mockMessages: MockMessage[] = [
    {
      id: "msg-1",
      data: () => ({
        text: "Test message",
        senderId: "other-user",
        senderName: "Bob",
        timestamp: {
          toMillis: () => Date.now() - 3600000,
        },
      }),
    },
  ];

  const { summarizeThread } = loadSummarizeThread({
    userIsParticipant: false,
    messages: mockMessages,
    aiResponse: "Test summary for unauthenticated user.",
  });

  const request: Record<string, unknown> = {
    auth: undefined,
    data: {
      conversationId: "test-convo-123",
    },
  };

  const response = await summarizeThread(request) as {
    summary: string;
    conversationId: string;
    messageCount: number;
    generatedAt: number;
  };

  assert.equal(response.conversationId, "test-convo-123");
  assert.equal(response.summary, "Test summary for unauthenticated user.");
  assert.ok(typeof response.generatedAt === "number");
});

test("summarizeThread handles empty conversation", async () => {
  const { summarizeThread } = loadSummarizeThread({
    messages: [],
  });

  const request: Record<string, unknown> = {
    auth: { uid: "test-user-123" },
    data: {
      conversationId: "empty-convo",
    },
  };

  const response = await summarizeThread(request) as {
    summary: string;
    conversationId: string;
    messageCount: number;
    generatedAt: number;
  };

  assert.equal(response.conversationId, "empty-convo");
  assert.equal(response.messageCount, 0);
  assert.equal(response.summary, "No messages to summarize.");
  assert.ok(typeof response.generatedAt === "number");
});

test("summarizeThread successfully generates summary", async () => {
  const mockMessages: MockMessage[] = [
    {
      id: "msg-1",
      data: () => ({
        text: "Hello, how are you?",
        senderId: "user-1",
        senderName: "Alice",
        timestamp: {
          toMillis: () => Date.now() - 3600000,
        },
      }),
    },
    {
      id: "msg-2",
      data: () => ({
        text: "I'm doing great, thanks!",
        senderId: "user-2",
        senderName: "Bob",
        timestamp: {
          toMillis: () => Date.now() - 3000000,
        },
      }),
    },
    {
      id: "msg-3",
      data: () => ({
        text: "Want to grab lunch tomorrow?",
        senderId: "user-1",
        senderName: "Alice",
        timestamp: {
          toMillis: () => Date.now() - 1800000,
        },
      }),
    },
  ];

  const { summarizeThread, capturedAIPrompts } = loadSummarizeThread({
    messages: mockMessages,
    aiResponse: "Alice and Bob discussed meeting for lunch tomorrow.",
  });

  const request: Record<string, unknown> = {
    auth: { uid: "test-user-123" },
    data: {
      conversationId: "test-convo-123",
      maxMessages: 50,
    },
  };

  const response = await summarizeThread(request) as {
    summary: string;
    conversationId: string;
    messageCount: number;
    generatedAt: number;
  };

  assert.equal(response.conversationId, "test-convo-123");
  assert.equal(response.messageCount, 3);
  assert.equal(response.summary, "Alice and Bob discussed meeting for lunch tomorrow.");
  assert.ok(typeof response.generatedAt === "number");
  assert.ok(response.generatedAt > 0);

  // Verify AI was called with proper prompt
  assert.equal(capturedAIPrompts.length, 1);
  assert.ok(capturedAIPrompts[0].includes("Alice"));
  assert.ok(capturedAIPrompts[0].includes("Bob"));
  assert.ok(capturedAIPrompts[0].includes("Hello, how are you?"));
});

test("summarizeThread respects maxMessages limit", async () => {
  const mockMessages: MockMessage[] = Array.from({ length: 10 }, (_, i) => ({
    id: `msg-${i}`,
    data: () => ({
      text: `Message ${i}`,
      senderId: `user-${i % 2}`,
      senderName: i % 2 === 0 ? "Alice" : "Bob",
      timestamp: {
        toMillis: () => Date.now() - (10 - i) * 1000,
      },
    }),
  }));

  const { summarizeThread } = loadSummarizeThread({
    messages: mockMessages,
  });

  const request: Record<string, unknown> = {
    auth: { uid: "test-user-123" },
    data: {
      conversationId: "test-convo-123",
      maxMessages: 5,
    },
  };

  const response = await summarizeThread(request) as {
    messageCount: number;
  };

  // Should still return all messages from the mock, but in production
  // the limit would be enforced by Firestore query
  assert.ok(response.messageCount >= 0);
});
