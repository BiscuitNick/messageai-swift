import test from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import * as https from "firebase-functions/v2/https";
type CreateBotsHandler = (request: Record<string, unknown>) => Promise<unknown>;

const modulePath = "../index";

function loadCreateBots(): {
  createBots: CreateBotsHandler;
  collectionCalls: () => number;
  capturedWrites: Record<string, Record<string, unknown>>;
} {
  const capturedWrites: Record<string, Record<string, unknown>> = {};
  let collectionCallCount = 0;

  const firestoreStub = {
    collection: (collectionName: string) => {
      collectionCallCount += 1;
      assert.equal(collectionName, "bots");
      return {
        doc: (docId: string) => ({
          set: async (data: Record<string, unknown>) => {
            capturedWrites[docId] = data;
          },
        }),
      };
    },
  };

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

  delete require.cache[require.resolve(modulePath)];
  const httpsAny = https as unknown as Record<string, unknown>;
  const originalOnCall = httpsAny.onCall;

  Object.defineProperty(httpsAny, "onCall", {
    configurable: true,
    writable: true,
    value: (handler: CreateBotsHandler) => handler,
  });

  const { createBots } = require(modulePath) as { createBots: CreateBotsHandler };

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
    createBots,
    collectionCalls: () => collectionCallCount,
    capturedWrites,
  };
}

test("createBots rejects unauthenticated requests", async () => {
  const { createBots } = loadCreateBots();

  const unauthenticatedContext: Record<string, unknown> = {
    auth: undefined,
  };

  await assert.rejects(
    async () => {
      await createBots(unauthenticatedContext);
    },
    (error: unknown) => {
      assert.ok(error instanceof https.HttpsError);
      assert.equal((error as https.HttpsError).code, "unauthenticated");
      return true;
    }
  );
});

test("createBots writes both bot definitions with expected fields", async () => {
  const {
    createBots,
    collectionCalls,
    capturedWrites,
  } = loadCreateBots();

  const response = await createBots({ auth: { uid: "user-123" } });

  assert.equal(collectionCalls(), 1);
  assert.deepEqual(response, {
    status: "success",
    created: ["dash-bot", "dad-bot"],
  });
  assert.deepEqual(Object.keys(capturedWrites).sort(), ["dad-bot", "dash-bot"]);

  const dashBot = capturedWrites["dash-bot"];
  const dadBot = capturedWrites["dad-bot"];

  assert.equal(dashBot.name, "Dash Bot");
  assert.equal(dashBot.category, "general");
  assert.ok(Array.isArray(dashBot.capabilities));
  assert.equal(dadBot.name, "Dad Bot");
  assert.equal(dadBot.category, "humor");
  assert.ok(Array.isArray(dadBot.capabilities));

  assert.ok("updatedAt" in dashBot);
  assert.ok("createdAt" in dashBot);
  assert.ok("updatedAt" in dadBot);
  assert.ok("createdAt" in dadBot);
});
