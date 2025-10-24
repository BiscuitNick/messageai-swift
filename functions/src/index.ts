import * as admin from "firebase-admin";

if (!admin.apps.length) {
  admin.initializeApp();
}

export * from "./ai/agents";
export * from "./ai/classifications";
export * from "./ai/coordination";
export * from "./ai/extractions";
export * from "./ai/search";
export * from "./ai/summarizations";
export * from "./ai/suggestions";
export * from "./bots";
export * from "./core/auth";
export * from "./core/config";
export * from "./core/constants";
export * from "./core/utils";
export * from "./data/mock";