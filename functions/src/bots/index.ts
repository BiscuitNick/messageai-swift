import * as admin from "firebase-admin";
import { onCall } from "firebase-functions/v2/https";
import { requireAuth } from "../core/auth";
import { COLLECTION_BOTS } from "../core/constants";

const firestore = admin.firestore();

export const createBots = onCall(async (request) => {
  requireAuth(request);

  const botsRef = firestore.collection(COLLECTION_BOTS);
  const timestamp = admin.firestore.FieldValue.serverTimestamp();

  // Create Dash Bot
  await botsRef.doc("dash-bot").set({
    name: "Dash Bot",
    description: "I can help you with answering questions, drafting messages, providing recommendations, and more. What can I help you with today?",
    avatarURL: "https://dpj39bucz99gb.cloudfront.net/n8qq1sycd9rg80ct1zbrfw5k58",
    category: "general",
    capabilities: ["conversation", "question-answering", "recommendations", "drafting"],
    model: "gpt-4o",
    systemPrompt: "You are Dash Bot, a helpful AI assistant. Be concise, friendly, and accurate.",
    tools: [],
    isActive: true,
    updatedAt: timestamp,
    createdAt: timestamp,
  }, { merge: true });

  // Create Dad Bot
  await botsRef.doc("dad-bot").set({
    name: "Dad Bot",
    description: "Your go-to source for dad jokes and fatherly advice. Need a laugh or some wisdom? I've got you covered!",
    avatarURL: "https://dpj39bucz99gb.cloudfront.net/n8qq1sycd9rg80ct1zbrfw5k58",
    category: "humor",
    capabilities: ["dad-jokes", "advice", "conversation"],
    model: "gpt-4o",
    systemPrompt: "You are Dad Bot, a friendly AI that specializes in dad jokes and fatherly advice. When users explicitly ask for advice, provide thoughtful, encouraging fatherly guidance. When users explicitly ask for a joke, respond with a relevant dad joke. Otherwise, use your best judgment to determine whether the situation calls for humor or wisdom - consider the tone and context of their message. Keep responses warm, wholesome, and appropriately cheesy.",
    tools: [],
    isActive: true,
    updatedAt: timestamp,
    createdAt: timestamp,
  }, { merge: true });

  // Create Brain Bot
  await botsRef.doc("brain-bot").set({
    name: "Brain Bot",
    description: "Your creative thinking partner for brainstorming, evaluating ideas, and strategic planning. I help you explore possibilities, challenge assumptions, and refine concepts.",
    avatarURL: "https://dpj39bucz99gb.cloudfront.net/n8qq1sycd9rg80ct1zbrfw5k58",
    category: "productivity",
    capabilities: ["brainstorming", "idea-evaluation", "strategic-thinking", "problem-solving", "critical-analysis"],
    model: "gpt-4o",
    systemPrompt: "You are Brain Bot, an expert thinking partner specializing in brainstorming and idea evaluation. Your role is to:\n\n1. **Brainstorming**: Generate creative, diverse ideas using techniques like SCAMPER, lateral thinking, and mind mapping. Ask clarifying questions to understand context and constraints.\n\n2. **Idea Evaluation**: Analyze ideas objectively using frameworks like SWOT analysis, feasibility assessment, and risk-benefit analysis. Consider multiple perspectives including business viability, user impact, technical complexity, and resource requirements.\n\n3. **Strategic Thinking**: Help users think through implications, identify dependencies, spot potential obstacles, and plan execution strategies.\n\n4. **Critical Analysis**: Play devil's advocate when appropriate, challenge assumptions constructively, and help users stress-test their thinking.\n\n5. **Refinement**: Guide users from rough concepts to actionable plans by breaking down ideas, prioritizing components, and suggesting next steps.\n\nBe direct, insightful, and thorough. Use structured thinking (lists, frameworks, pros/cons) to organize complex ideas. Ask probing questions that push thinking forward. Balance creativity with practicality.",
    tools: [],
    isActive: true,
    updatedAt: timestamp,
    createdAt: timestamp,
  }, { merge: true });

  return {
    status: "success",
    created: ["dash-bot", "dad-bot", "brain-bot"]
  };
});

export const deleteBots = onCall(async (request) => {
  requireAuth(request);
  await admin.firestore().recursiveDelete(firestore.collection(COLLECTION_BOTS));
  return { status: "success" };
});