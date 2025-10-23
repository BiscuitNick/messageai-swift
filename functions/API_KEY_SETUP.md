# OpenAI API Key Setup Guide

## Step 1: Get Your OpenAI API Key

1. Go to https://platform.openai.com/api-keys
2. Sign up or log in
3. Click **"Create new secret key"**
4. Give it a name (e.g., "Firebase Functions")
5. **Copy the key** (starts with `sk-`) - you won't see it again!

## Step 2: Set Up for Local Development

1. In the `functions` directory, create a `.env` file:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` and add your actual API key:
   ```
   OPENAI_API_KEY=sk-your-actual-key-here
   ```

3. Test locally:
   ```bash
   npm run serve
   ```

## Step 3: Deploy to Production

When you deploy, Firebase will prompt you for the API key value:

```bash
npm run deploy
```

You'll see a prompt like:
```
? Enter a value for OPENAI_API_KEY:
```

Paste your API key there.

### Alternative: Set via Firebase Console

You can also set it manually in the Firebase Console:

1. Go to https://console.firebase.google.com
2. Select your project
3. Go to **Functions** → **Settings** → **Environment Variables**
4. Add variable: `OPENAI_API_KEY` = `sk-your-key`

## Important Notes

- **Never commit** your `.env` file to git (it's already in `.gitignore`)
- Keep your API key secret
- Monitor usage at https://platform.openai.com/usage
- The function uses GPT-4o-mini by default (cost-effective)

## Estimated Costs

GPT-4o-mini pricing (as of 2024):
- Input: $0.15 per 1M tokens
- Output: $0.60 per 1M tokens

A typical conversation message:
- ~100-500 tokens input
- ~100-300 tokens output
- Cost: ~$0.0001-0.0005 per message

## Testing the Function

Once deployed, test from your iOS app:

```swift
let result = try await functions.httpsCallable("chatWithAgent").call([
    "prompt": "Hello, can you help me?"
])
```

Or test with curl:
```bash
curl -X POST \
  -H "Authorization: Bearer $(firebase functions:config:get)" \
  -H "Content-Type: application/json" \
  -d '{"data":{"prompt":"Hello"}}' \
  https://us-central1-YOUR-PROJECT-ID.cloudfunctions.net/chatWithAgent
```
