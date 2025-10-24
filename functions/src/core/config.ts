import { setGlobalOptions } from "firebase-functions/v2/options";

import { createOpenAI } from "@ai-sdk/openai";

setGlobalOptions({ region: "us-central1" });

// Define OpenAI API key as an environment parameter


export const openai = createOpenAI({
    apiKey: process.env.OPENAI_API_KEY,
});