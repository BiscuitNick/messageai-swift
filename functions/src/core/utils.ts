import * as admin from "firebase-admin";
import { onCall } from "firebase-functions/v2/https";

const firestore = admin.firestore();
const COLLECTION_USERS = "users";
const COLLECTION_BOTS = "bots";

export const getServerTime = onCall(async () => {
  const now = admin.firestore.Timestamp.now();
  return {
    iso: now.toDate().toISOString(),
    seconds: now.seconds,
    nanoseconds: now.nanoseconds,
  };
});

export async function fetchSenderNames(senderIds: string[]): Promise<Record<string, string>> {
    const senderNames: Record<string, string> = {};
  
    await Promise.all(
      senderIds.map(async (senderId) => {
        if (senderId.startsWith("bot:")) {
          const botId = senderId.replace("bot:", "");
          const botDoc = await firestore.collection(COLLECTION_BOTS).doc(botId).get();
          senderNames[senderId] = botDoc.exists ? (botDoc.data()?.name as string || "Bot") : "Bot";
        } else {
          const userDoc = await firestore.collection(COLLECTION_USERS).doc(senderId).get();
          senderNames[senderId] = userDoc.exists
            ? (userDoc.data()?.displayName as string || "Unknown")
            : "Unknown";
        }
      })
    );
  
    return senderNames;
  }