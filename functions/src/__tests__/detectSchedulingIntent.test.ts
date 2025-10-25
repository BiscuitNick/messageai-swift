import test from "node:test";
import assert from "node:assert/strict";

type DetectSchedulingIntentHandler = (event: Record<string, unknown>) => Promise<void>;

const modulePath = "../index";

function loadDetectSchedulingIntent(options: {
  mockOpenAIResponse?: unknown;
  shouldReturnError?: boolean;
}): {
  detectSchedulingIntent: DetectSchedulingIntentHandler;
  capturedOpenAICalls: Array<{ system: string; prompt: string }>;
  capturedWrites: Record<string, Record<string, unknown>>;
} {
  const { mockOpenAIResponse, shouldReturnError = false } = options;

  const capturedOpenAICalls: Array<{ system: string; prompt: string }> = [];
  const capturedWrites: Record<string, Record<string, unknown>> = {};

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

    const defaultResponse = mockOpenAIResponse || {
      hasSchedulingIntent: true,
      confidence: 0.85,
      reasoning: "Message contains explicit scheduling request",
      suggestedKeywords: ["let's meet", "schedule"],
    };

    return { object: defaultResponse };
  };

  const mockTool = (config: unknown) => config;

  const mockExperimentalAgent = class {
    constructor() {}
    generate() {
      return Promise.resolve({
        text: "Mock response",
        usage: { totalTokens: 100 },
      });
    }
  };

  // Mock require to inject AI SDK mocks
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

  // Mock firebase-functions/v2/firestore
  const firestore = require("firebase-functions/v2/firestore");
  const originalOnDocumentCreated = firestore.onDocumentCreated;

  (firestore as Record<string, unknown>).onDocumentCreated = (
    path: string,
    handler: DetectSchedulingIntentHandler
  ) => handler;

  delete require.cache[require.resolve(modulePath)];
  const { detectSchedulingIntent } = require(modulePath) as {
    detectSchedulingIntent: DetectSchedulingIntentHandler;
  };

  // Restore mocks
  Module.prototype.require = originalRequire;
  (firestore as Record<string, unknown>).onDocumentCreated = originalOnDocumentCreated;

  return {
    detectSchedulingIntent,
    capturedOpenAICalls,
    capturedWrites,
  };
}

function createMockEvent(messageData: Record<string, unknown>): Record<string, unknown> {
  const writtenData: Record<string, unknown> = {};

  return {
    params: {
      conversationId: "conv-123",
      messageId: "msg-456",
    },
    data: {
      data: () => messageData,
      ref: {
        set: async (data: Record<string, unknown>, options: { merge: boolean }) => {
          Object.assign(writtenData, data);
          return writtenData;
        },
      },
    },
    _writtenData: writtenData,
  };
}

test("detectSchedulingIntent skips messages without data", async () => {
  const { detectSchedulingIntent, capturedOpenAICalls } = loadDetectSchedulingIntent({});

  const event = {
    params: { conversationId: "conv-123", messageId: "msg-456" },
    data: null,
  };

  await detectSchedulingIntent(event);

  // Should not call OpenAI if no message data
  assert.equal(capturedOpenAICalls.length, 0);
});

test("detectSchedulingIntent skips messages from bots", async () => {
  const { detectSchedulingIntent, capturedOpenAICalls } = loadDetectSchedulingIntent({});

  const event = createMockEvent({
    senderId: "bot:dash-bot",
    text: "Let's schedule a meeting",
  });

  await detectSchedulingIntent(event);

  // Should not call OpenAI for bot messages
  assert.equal(capturedOpenAICalls.length, 0);
});

test("detectSchedulingIntent skips system messages", async () => {
  const { detectSchedulingIntent, capturedOpenAICalls } = loadDetectSchedulingIntent({});

  const event = createMockEvent({
    senderId: "user-123",
    text: "User joined the conversation",
    isSystemMessage: true,
  });

  await detectSchedulingIntent(event);

  // Should not call OpenAI for system messages
  assert.equal(capturedOpenAICalls.length, 0);
});

test("detectSchedulingIntent skips already analyzed messages", async () => {
  const { detectSchedulingIntent, capturedOpenAICalls } = loadDetectSchedulingIntent({});

  const event = createMockEvent({
    senderId: "user-123",
    text: "Let's meet tomorrow",
    schedulingIntentAnalyzedAt: new Date(),
  });

  await detectSchedulingIntent(event);

  // Should not call OpenAI if already analyzed
  assert.equal(capturedOpenAICalls.length, 0);
});

test("detectSchedulingIntent classifies message with high confidence", async () => {
  const { detectSchedulingIntent, capturedOpenAICalls } = loadDetectSchedulingIntent({
    mockOpenAIResponse: {
      hasSchedulingIntent: true,
      confidence: 0.9,
      reasoning: "Explicit scheduling request with time reference",
      suggestedKeywords: ["meet tomorrow", "schedule"],
    },
  });

  const messageText = "Hey, can we meet tomorrow at 2pm?";
  const event = createMockEvent({
    senderId: "user-123",
    text: messageText,
  });

  await detectSchedulingIntent(event);

  // Verify OpenAI was called with correct message
  assert.equal(capturedOpenAICalls.length, 1);
  assert.ok(capturedOpenAICalls[0].prompt.includes(messageText));
  assert.ok(capturedOpenAICalls[0].system.includes("scheduling intent classifier"));

  // Verify data was written to Firestore
  const writtenData = (event as Record<string, unknown>)._writtenData as Record<string, unknown>;
  assert.equal(writtenData.schedulingIntent, true);
  assert.equal(writtenData.schedulingIntentConfidence, 0.9);
  assert.ok(writtenData.schedulingIntentReasoning);
  assert.ok(Array.isArray(writtenData.schedulingIntentKeywords));
  assert.ok(writtenData.schedulingIntentAnalyzedAt);
});

test("detectSchedulingIntent classifies message with medium confidence", async () => {
  const { detectSchedulingIntent } = loadDetectSchedulingIntent({
    mockOpenAIResponse: {
      hasSchedulingIntent: true,
      confidence: 0.6,
      reasoning: "Implied scheduling need",
      suggestedKeywords: ["catch up"],
    },
  });

  const event = createMockEvent({
    senderId: "user-456",
    text: "We should catch up soon",
  });

  await detectSchedulingIntent(event);

  const writtenData = (event as Record<string, unknown>)._writtenData as Record<string, unknown>;
  assert.equal(writtenData.schedulingIntent, true);
  assert.equal(writtenData.schedulingIntentConfidence, 0.6);
});

test("detectSchedulingIntent classifies message with low confidence", async () => {
  const { detectSchedulingIntent } = loadDetectSchedulingIntent({
    mockOpenAIResponse: {
      hasSchedulingIntent: false,
      confidence: 0.2,
      reasoning: "No clear scheduling intent",
      suggestedKeywords: [],
    },
  });

  const event = createMockEvent({
    senderId: "user-789",
    text: "That's great!",
  });

  await detectSchedulingIntent(event);

  const writtenData = (event as Record<string, unknown>)._writtenData as Record<string, unknown>;
  assert.equal(writtenData.schedulingIntent, false);
  assert.equal(writtenData.schedulingIntentConfidence, 0.2);
  assert.ok(writtenData.schedulingIntentAnalyzedAt);
  // Low confidence messages should not have keywords or reasoning
  assert.ok(!writtenData.schedulingIntentKeywords);
  assert.ok(!writtenData.schedulingIntentReasoning);
});

test("detectSchedulingIntent handles OpenAI errors gracefully", async () => {
  const { detectSchedulingIntent, capturedOpenAICalls } = loadDetectSchedulingIntent({
    shouldReturnError: true,
  });

  const event = createMockEvent({
    senderId: "user-123",
    text: "Let's schedule a meeting",
  });

  // Should not throw
  await detectSchedulingIntent(event);

  // OpenAI should have been called
  assert.equal(capturedOpenAICalls.length, 1);

  // Default no-intent data should be written after error
  const writtenData = (event as Record<string, unknown>)._writtenData as Record<string, unknown>;
  assert.equal(writtenData.schedulingIntent, false);
  assert.equal(writtenData.schedulingIntentConfidence, 0);
  assert.ok(writtenData.schedulingIntentAnalyzedAt);
});

test("detectSchedulingIntent threshold at 0.4 confidence", async () => {
  // Test exactly at threshold
  const { detectSchedulingIntent } = loadDetectSchedulingIntent({
    mockOpenAIResponse: {
      hasSchedulingIntent: true,
      confidence: 0.4,
      reasoning: "Borderline scheduling intent",
      suggestedKeywords: ["time"],
    },
  });

  const event = createMockEvent({
    senderId: "user-123",
    text: "Do you have time?",
  });

  await detectSchedulingIntent(event);

  const writtenData = (event as Record<string, unknown>)._writtenData as Record<string, unknown>;
  // At threshold, should write full data
  assert.equal(writtenData.schedulingIntent, true);
  assert.equal(writtenData.schedulingIntentConfidence, 0.4);
  assert.ok(writtenData.schedulingIntentKeywords);
});

test("detectSchedulingIntent just below threshold", async () => {
  // Test just below threshold
  const { detectSchedulingIntent } = loadDetectSchedulingIntent({
    mockOpenAIResponse: {
      hasSchedulingIntent: false,
      confidence: 0.39,
      reasoning: "Below threshold",
      suggestedKeywords: [],
    },
  });

  const event = createMockEvent({
    senderId: "user-123",
    text: "What time is it?",
  });

  await detectSchedulingIntent(event);

  const writtenData = (event as Record<string, unknown>)._writtenData as Record<string, unknown>;
  // Below threshold, should only write minimal data
  assert.equal(writtenData.schedulingIntent, false);
  assert.equal(writtenData.schedulingIntentConfidence, 0.39);
  assert.ok(!writtenData.schedulingIntentKeywords);
  assert.ok(!writtenData.schedulingIntentReasoning);
});

test("detectSchedulingIntent extracts scheduling keywords", async () => {
  const { detectSchedulingIntent } = loadDetectSchedulingIntent({
    mockOpenAIResponse: {
      hasSchedulingIntent: true,
      confidence: 0.95,
      reasoning: "Multiple scheduling indicators",
      suggestedKeywords: ["schedule a call", "next week", "find a time"],
    },
  });

  const event = createMockEvent({
    senderId: "user-123",
    text: "Can we schedule a call for next week? Let's find a time that works.",
  });

  await detectSchedulingIntent(event);

  const writtenData = (event as Record<string, unknown>)._writtenData as Record<string, unknown>;
  assert.equal(writtenData.schedulingIntent, true);
  assert.ok(Array.isArray(writtenData.schedulingIntentKeywords));
  assert.equal((writtenData.schedulingIntentKeywords as string[]).length, 3);
  assert.ok((writtenData.schedulingIntentKeywords as string[]).includes("schedule a call"));
});
