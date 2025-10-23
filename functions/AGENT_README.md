# AI Agent Firebase Function

This Firebase function provides an AI agent powered by Vercel's AI SDK and OpenAI's GPT-4o-mini model.

## Features

- Conversational AI assistant integrated into your messaging app
- Tool support for extended capabilities:
  - `getCurrentTime`: Get current date and time
  - `draftMessage`: Help draft messages with different tones
- Support for both single prompts and multi-turn conversations
- Authentication required for all requests

## Setup

### 1. Environment Variables

Set your OpenAI API key in Firebase Functions:

```bash
firebase functions:config:set openai.api_key="your-openai-api-key"
```

Or for local development, create a `.env.local` file:

```
OPENAI_API_KEY=your-openai-api-key
```

### 2. Deploy

Deploy the function to Firebase:

```bash
npm run deploy
```

## Swift Integration

### Setup Firebase Functions in Swift

First, ensure you have Firebase Functions configured in your iOS app:

```swift
import FirebaseFunctions

let functions = Functions.functions()
```

### Example 1: Simple Prompt

```swift
func chatWithAgent(prompt: String) async throws -> String {
    let data: [String: Any] = [
        "prompt": prompt
    ]

    let result = try await functions.httpsCallable("chatWithAgent").call(data)

    guard let response = result.data as? [String: Any],
          let text = response["response"] as? String else {
        throw NSError(domain: "AgentError", code: -1,
                     userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
    }

    return text
}

// Usage
Task {
    let response = try await chatWithAgent(prompt: "What's the weather like?")
    print(response)
}
```

### Example 2: Conversation with Message History

```swift
struct AgentMessage: Codable {
    let role: String // "user" or "assistant"
    let content: String
}

func chatWithHistory(messages: [AgentMessage]) async throws -> String {
    let messagesData = messages.map { message in
        return [
            "role": message.role,
            "content": message.content
        ]
    }

    let data: [String: Any] = [
        "messages": messagesData
    ]

    let result = try await functions.httpsCallable("chatWithAgent").call(data)

    guard let response = result.data as? [String: Any],
          let text = response["response"] as? String else {
        throw NSError(domain: "AgentError", code: -1,
                     userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
    }

    return text
}

// Usage
Task {
    let messages = [
        AgentMessage(role: "user", content: "Hello!"),
        AgentMessage(role: "assistant", content: "Hi! How can I help you?"),
        AgentMessage(role: "user", content: "What time is it?")
    ]
    let response = try await chatWithHistory(messages: messages)
    print(response)
}
```

### Example 3: SwiftUI Integration

```swift
import SwiftUI
import FirebaseFunctions

class AgentViewModel: ObservableObject {
    @Published var messages: [AgentMessage] = []
    @Published var isLoading = false
    @Published var error: String?

    private let functions = Functions.functions()

    func sendMessage(_ text: String) async {
        await MainActor.run {
            messages.append(AgentMessage(role: "user", content: text))
            isLoading = true
            error = nil
        }

        do {
            let messagesData = messages.map { ["role": $0.role, "content": $0.content] }
            let data: [String: Any] = ["messages": messagesData]

            let result = try await functions.httpsCallable("chatWithAgent").call(data)

            guard let response = result.data as? [String: Any],
                  let text = response["response"] as? String else {
                throw NSError(domain: "AgentError", code: -1)
            }

            await MainActor.run {
                messages.append(AgentMessage(role: "assistant", content: text))
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

struct AgentChatView: View {
    @StateObject private var viewModel = AgentViewModel()
    @State private var inputText = ""

    var body: some View {
        VStack {
            ScrollView {
                ForEach(viewModel.messages.indices, id: \.self) { index in
                    let message = viewModel.messages[index]
                    HStack {
                        if message.role == "user" {
                            Spacer()
                            Text(message.content)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        } else {
                            Text(message.content)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(10)
                            Spacer()
                        }
                    }
                    .padding(.horizontal)
                }
            }

            if viewModel.isLoading {
                ProgressView()
            }

            if let error = viewModel.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack {
                TextField("Message", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Send") {
                    Task {
                        await viewModel.sendMessage(inputText)
                        inputText = ""
                    }
                }
                .disabled(inputText.isEmpty || viewModel.isLoading)
            }
            .padding()
        }
    }
}
```

## API Reference

### Request Format

```typescript
{
  // Option 1: Single prompt
  "prompt": "Your question or message"

  // Option 2: Message history
  "messages": [
    { "role": "user", "content": "Hello" },
    { "role": "assistant", "content": "Hi there!" },
    { "role": "user", "content": "How are you?" }
  ]
}
```

### Response Format

```typescript
{
  "response": "The agent's text response",
  "usage": {
    "promptTokens": 123,
    "completionTokens": 45,
    "totalTokens": 168
  }
}
```

## Customization

### Adding New Tools

To add custom tools to the agent, edit `src/index.ts`:

```typescript
const assistantAgent = new Agent({
  model: openai("gpt-4o-mini"),
  system: "Your system prompt",
  tools: {
    yourCustomTool: tool({
      description: "What this tool does",
      inputSchema: z.object({
        param1: z.string().describe("Description"),
      }),
      execute: async ({ param1 }) => {
        // Your tool implementation
        return { result: "..." };
      },
    }),
  },
});
```

### Changing the Model

To use a different OpenAI model:

```typescript
model: openai("gpt-4o") // or "gpt-3.5-turbo", etc.
```

## Error Handling

The function will throw Firebase HTTPS errors:

- `unauthenticated`: User is not authenticated
- `invalid-argument`: Missing required parameters
- `internal`: Agent processing failed

Make sure to handle these in your Swift code:

```swift
do {
    let response = try await chatWithAgent(prompt: "Hello")
} catch let error as NSError {
    switch error.domain {
    case "FunctionsErrorDomain":
        // Handle Firebase Functions errors
        print("Error code: \(error.code)")
    default:
        print("Unknown error: \(error)")
    }
}
```

## Testing Locally

Run the Firebase emulator:

```bash
npm run serve
```

Then update your Swift app to use the emulator:

```swift
#if DEBUG
functions.useEmulator(withHost: "localhost", port: 5001)
#endif
```
