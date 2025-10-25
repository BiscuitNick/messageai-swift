# MessageAI

> AI-powered messaging platform with intelligent features for iOS

MessageAI is a modern messaging application built with Swift and Firebase that integrates AI capabilities for enhanced communication. Features include AI chat bots, action item extraction, priority classification, meeting scheduling assistance, and conversation summarization.

---

## 📋 Table of Contents

- [Features](#features)
- [Tech Stack](#tech-stack)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Project Structure](#project-structure)
- [Development](#development)
- [Testing](#testing)
- [Deployment](#deployment)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

---

## ✨ Features

### Core Messaging
- **Real-time messaging** with Firestore sync
- **Direct and group conversations**
- **Read receipts** and delivery status
- **Typing indicators**
- **Unread message tracking**

### AI-Powered Features
- **AI Chat Bots** - Conversational AI assistants (Dash Bot, Dad Bot)
- **Action Item Extraction** - Automatically identify tasks from conversations
- **Priority Classification** - AI-based message priority scoring
- **Meeting Scheduling** - Smart detection of scheduling intent and time suggestions
- **Thread Summarization** - Generate conversation summaries with key points
- **Decision Tracking** - Extract and track important decisions
- **Smart Search** - Semantic search across conversations
- **Coordination Dashboard** - Proactive insights and alerts for team coordination

#### AI Quality & Resilience
- **Retry Logic** - Exponential backoff with jitter for transient failures (max 3 attempts)
- **Smart Caching** - SwiftData persistence with TTL (24h for summaries, 1h for search results)
- **Telemetry** - Comprehensive metrics tracking (latency, success/failure, retry attempts)
- **User Feedback** - In-app feedback submission for AI-generated content quality improvement

### User Experience
- **SwiftUI** interface with smooth animations
- **Offline support** with local SwiftData cache
- **Profile pictures** and avatars
- **Dark mode** support

---

## 🛠 Tech Stack

### iOS App
- **SwiftUI** - Declarative UI framework
- **SwiftData** - Local data persistence
- **Firebase Auth** - User authentication
- **Firebase Firestore** - Real-time database
- **Firebase Functions** - Cloud functions client
- **Firebase Storage** - File storage

### Backend (Firebase Functions)
- **TypeScript** - Type-safe cloud functions
- **Firebase Admin SDK** - Server-side Firebase operations
- **OpenAI GPT-4o-mini** - AI model for intelligent features
- **Vercel AI SDK** - Structured AI outputs with Zod schemas

---

## 🏗 Architecture

### High-Level Overview

```
┌─────────────────────────────────────────────────────────────┐
│                       iOS App (Swift)                       │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐   │
│  │   SwiftUI   │  │  SwiftData   │  │  Firebase SDK   │   │
│  │   Views     │──│   Cache      │──│   Auth/DB       │   │
│  └─────────────┘  └──────────────┘  └─────────────────┘   │
└────────────────────────────┬────────────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │  Firebase Auth  │
                    └────────┬────────┘
                             │
            ┌────────────────┼────────────────┐
            │                │                │
    ┌───────▼──────┐  ┌─────▼──────┐  ┌─────▼─────────┐
    │  Firestore   │  │  Storage   │  │   Functions   │
    │   Database   │  │   (Files)  │  │  (Backend)    │
    └──────────────┘  └────────────┘  └───────┬───────┘
                                              │
                                      ┌───────▼────────┐
                                      │  OpenAI API    │
                                      │  (GPT-4o-mini) │
                                      └────────────────┘
```

### AI Resilience & Quality Architecture

MessageAI implements comprehensive quality controls for AI features to ensure reliability and continuous improvement:

```
┌─────────────────────────────────────────────────────────────┐
│                   AI Call with Resilience                   │
└─────────────────────────────────────────────────────────────┘

User Triggers AI Feature
       │
       ▼
┌──────────────────────────┐
│   AIFeaturesService      │
│   callWithRetry()        │
└──────────┬───────────────┘
           │
           ▼
    ┌──────────────┐
    │ Check Cache  │──────► Cache Hit? Return Immediately
    │ (SwiftData)  │        (24h for summaries, 1h for search)
    └──────┬───────┘
           │ Cache Miss
           ▼
    ┌──────────────────┐
    │ Start Telemetry  │──► Track: userId, function, startTime
    │ Tracking         │
    └──────┬───────────┘
           │
           ▼
    ┌──────────────────┐
    │ Call Firebase    │
    │ Function         │
    └──────┬───────────┘
           │
      ┌────┴────┐
      │         │
   Success    Failure
      │         │
      │         ▼
      │    ┌────────────────┐
      │    │ Is Retryable?  │──No──► Log Failure Telemetry
      │    │ (Network/500)  │        Throw Error
      │    └────┬───────────┘
      │         │ Yes
      │         ▼
      │    ┌────────────────┐
      │    │ Exponential    │
      │    │ Backoff + Jitter│
      │    │ (0.5s → 8s max)│
      │    └────┬───────────┘
      │         │
      │         └──────► Retry (Max 3 attempts)
      │
      ▼
┌─────────────────┐
│ Log Success     │──► Firestore: ai_telemetry/
│ Telemetry       │    - durationMs, attemptCount, success
└─────┬───────────┘
      │
      ▼
┌─────────────────┐
│ Cache Result    │──► SwiftData with TTL expiration
│ (if applicable) │
└─────┬───────────┘
      │
      ▼
   Return to User
      │
      ▼
┌─────────────────┐
│ User Can Submit │──► Firestore: ai_feedback/
│ Feedback        │    - rating (1-5), correction, comment
└─────────────────┘
```

### Data Flow Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         Message Flow                             │
└──────────────────────────────────────────────────────────────────┘

User Types Message
       │
       ▼
┌──────────────┐
│ MessagingService │────► Write to Firestore
└──────────────┘           │
                          ▼
                   ┌──────────────┐
                   │  Firestore    │
                   │  /messages    │
                   └──────┬────────┘
                          │
            ┌─────────────┼─────────────┐
            │             │             │
            ▼             ▼             ▼
    ┌───────────┐  ┌───────────┐  ┌────────────┐
    │ Priority  │  │Scheduling │  │  Message   │
    │ Trigger   │  │  Trigger  │  │  Listener  │
    └─────┬─────┘  └─────┬─────┘  └─────┬──────┘
          │              │              │
          ▼              ▼              ▼
    Classify ───►  Detect ───►   Update SwiftData
    Priority      Intent        Cache
```

### AI Features Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AI Features Flow                         │
└─────────────────────────────────────────────────────────────┘

User Triggers AI Feature (e.g., "Extract Action Items")
       │
       ▼
┌──────────────────┐
│ AIFeaturesService │
└────────┬──────────┘
         │
         ▼
┌─────────────────────┐
│ Firebase Function   │
│ (extractActionItems)│
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  Fetch Messages     │
│  from Firestore     │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  OpenAI GPT-4o      │
│  Analyze & Extract  │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ Write Results to    │
│ Firestore           │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ Firestore Listener  │
│ Updates SwiftData   │
└─────────────────────┘
```

### Firebase Collections Structure

```
firestore/
├── users/
│   └── {userId}
│       ├── email: string
│       ├── displayName: string
│       ├── profilePictureURL: string
│       ├── isOnline: boolean
│       ├── lastSeen: timestamp
│       └── createdAt: timestamp
│
├── bots/
│   └── {botId}
│       ├── name: string
│       ├── description: string
│       ├── systemPrompt: string
│       ├── model: string
│       └── capabilities: array
│
├── conversations/
│   └── {conversationId}
│       ├── participantIds: array
│       ├── isGroup: boolean
│       ├── groupName: string
│       ├── lastMessage: string
│       ├── lastMessageTimestamp: timestamp
│       ├── lastSenderId: string
│       ├── unreadCount: map<userId, count>
│       ├── lastInteractionByUser: map<userId, timestamp>
│       │
│       ├── messages/
│       │   └── {messageId}
│       │       ├── conversationId: string
│       │       ├── senderId: string
│       │       ├── text: string
│       │       ├── timestamp: timestamp
│       │       ├── deliveryStatus: string
│       │       ├── readReceipts: map<userId, timestamp>
│       │       ├── priorityScore: number
│       │       ├── priorityLabel: string
│       │       ├── schedulingIntent: string
│       │       └── intentConfidence: number
│       │
│       ├── actionItems/
│       │   └── {actionItemId}
│       │       ├── task: string
│       │       ├── assignedTo: string
│       │       ├── dueDate: timestamp
│       │       ├── priority: string
│       │       ├── status: string
│       │       └── conversationId: string
│       │
│       └── decisions/
│           └── {decisionId}
│               ├── decisionText: string
│               ├── contextSummary: string
│               ├── participantIds: array
│               ├── decidedAt: timestamp
│               └── confidenceScore: number
│
├── ai_telemetry/
│   └── {eventId}
│       ├── userId: string
│       ├── functionName: string
│       ├── startTime: timestamp
│       ├── endTime: timestamp
│       ├── durationMs: number
│       ├── success: boolean
│       ├── attemptCount: number
│       ├── errorType: string (optional)
│       ├── errorMessage: string (optional)
│       ├── cacheHit: boolean
│       └── timestamp: timestamp
│
└── ai_feedback/
    └── {feedbackId}
        ├── userId: string
        ├── conversationId: string
        ├── featureType: string (summary, action_items, etc.)
        ├── originalContent: string
        ├── userCorrection: string (optional)
        ├── rating: number (1-5 stars)
        ├── comment: string (optional)
        ├── metadata: map (optional)
        └── timestamp: timestamp
```

---

## 📦 Prerequisites

### Required Software

1. **Xcode 15+**
   - Download from [Mac App Store](https://apps.apple.com/us/app/xcode/id497799835)
   - Includes Swift 5.9+

2. **Node.js 18+**
   ```bash
   # Using Homebrew
   brew install node

   # Verify installation
   node --version  # Should be 18.x or higher
   npm --version
   ```

3. **Firebase CLI**
   ```bash
   npm install -g firebase-tools

   # Login to Firebase
   firebase login
   ```

4. **CocoaPods** (if needed)
   ```bash
   sudo gem install cocoapods
   ```

### Required Accounts

1. **Apple Developer Account** (for iOS development)
   - Sign up at [developer.apple.com](https://developer.apple.com)

2. **Firebase/Google Cloud Account**
   - Create project at [firebase.google.com](https://firebase.google.com)

3. **OpenAI API Account** (for AI features)
   - Get API key at [platform.openai.com](https://platform.openai.com)

---

## 🚀 Quick Start

```bash
# 1. Clone the repository
git clone <repository-url>
cd messageai-swift-tests

# 2. Install Firebase Functions dependencies
cd functions
npm install
cd ..

# 3. Configure Firebase
# - Create a new Firebase project
# - Download GoogleService-Info.plist
# - Place in messageai-swift/ directory

# 4. Set up environment variables
cd functions
cp .env.example .env
# Edit .env and add your OPENAI_API_KEY

# 5. Deploy Firebase Functions
npm run deploy

# 6. Open iOS project
open messageai-swift.xcodeproj

# 7. Build and run in Xcode (⌘ + R)
```

---

## 🔧 Detailed Setup

### Step 1: Firebase Project Setup

#### 1.1 Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Click **"Add project"**
3. Enter project name: `messageai-swift` (or your choice)
4. Enable Google Analytics (optional)
5. Click **"Create project"**

#### 1.2 Enable Firebase Services

**Authentication:**
1. Navigate to **Authentication** → **Sign-in method**
2. Enable **Email/Password**
3. Enable **Google** (optional)

**Firestore Database:**
1. Navigate to **Firestore Database**
2. Click **"Create database"**
3. Choose **"Start in test mode"** (for development)
4. Select a location (choose closest to your users)

**Storage:**
1. Navigate to **Storage**
2. Click **"Get started"**
3. Use default security rules for now

#### 1.3 Configure iOS App

1. In Firebase Console, click **"Add app"** → **iOS**
2. Enter Bundle ID: `Nick-Kenkel.messageai-swift` (match Xcode project)
3. Download **`GoogleService-Info.plist`**
4. Drag file into Xcode project under `messageai-swift/` folder
5. Ensure "Copy items if needed" is checked

### Step 2: Firebase Functions Setup

#### 2.1 Install Dependencies

```bash
cd functions
npm install
```

#### 2.2 Configure Environment Variables

Create `.env` file in `functions/` directory:

```bash
# OpenAI API Key (required for AI features)
OPENAI_API_KEY=sk-...your-key-here...

# Optional: Other AI providers
PERPLEXITY_API_KEY=pplx-...
GOOGLE_API_KEY=...
```

#### 2.3 Review Functions Structure

```
functions/
├── src/
│   ├── ai/
│   │   ├── agents.ts           # AI chat bot logic
│   │   ├── classifications.ts  # Priority & scheduling detection
│   │   ├── extractions.ts      # Action items & decisions
│   │   ├── search.ts          # Smart search
│   │   ├── suggestions.ts     # Meeting time suggestions
│   │   └── summarizations.ts  # Thread summaries
│   ├── bots/
│   │   └── index.ts           # Bot creation/management
│   ├── core/
│   │   ├── auth.ts            # Authentication helpers
│   │   ├── config.ts          # Firebase config
│   │   ├── constants.ts       # Shared constants
│   │   └── utils.ts           # Utility functions
│   ├── data/
│   │   └── mock.ts            # Mock data generation
│   └── index.ts               # Main exports
├── package.json
└── tsconfig.json
```

#### 2.4 Build Functions

```bash
npm run build
```

#### 2.5 Deploy to Firebase

```bash
# Deploy all functions
npm run deploy

# Or deploy specific functions
firebase deploy --only functions:chatWithAgent
firebase deploy --only functions:extractActionItems
```

### Step 3: iOS App Setup

#### 3.1 Open Project in Xcode

```bash
cd messageai-swift-tests
open messageai-swift.xcodeproj
```

#### 3.2 Configure Signing

1. Select **messageai-swift** target in Xcode
2. Go to **Signing & Capabilities**
3. Select your **Team**
4. Ensure **Bundle Identifier** is unique

#### 3.3 Review Project Structure

```
messageai-swift/
├── App/
│   └── messageai_swiftApp.swift        # App entry point
├── Models/
│   ├── Models.swift                    # SwiftData entities with TTL support
│   └── AIModels.swift                  # AI response models
├── Views/
│   ├── AuthenticationView.swift       # Login/signup
│   ├── ConversationsListView.swift    # Conversation list
│   ├── ChatView.swift                  # Chat interface
│   ├── ActionItemsTabView.swift       # Action items UI
│   ├── DecisionsTabView.swift         # Decisions UI
│   ├── CoordinationDashboardView.swift # Team coordination insights
│   ├── ThreadSummaryCard.swift        # Summary display with feedback
│   └── AIFeedbackSheet.swift          # AI feedback submission UI
├── Services/
│   ├── AuthService.swift               # Authentication logic
│   ├── MessagingService.swift          # Messaging logic
│   ├── FirestoreService.swift          # Database operations
│   ├── AIFeaturesService.swift         # AI features with retry, caching, telemetry
│   ├── NotificationService.swift       # Local notifications
│   └── NetworkMonitor.swift            # Network connectivity monitoring
├── GoogleService-Info.plist            # Firebase config
└── Info.plist
```

#### 3.4 Build and Run

1. Select simulator or device
2. Press **⌘ + R** to build and run
3. Create an account or sign in
4. Start messaging!

### Step 4: Initialize Bots

After deploying functions, create the default bots:

```bash
# Using Firebase CLI
firebase functions:shell

# In the shell, run:
createBots()
```

Or call from your Swift app:

```swift
try await Functions.functions().httpsCallable("createBots").call()
```

### Step 5: (Optional) Generate Mock Data

For testing, generate mock conversations:

```swift
// In your Swift app
try await Functions.functions().httpsCallable("generateMockData").call()
```

This creates:
- 4 mock users (Alex, Priya, Sam, Jordan)
- 2 direct conversations
- 1 group conversation ("Product Squad")
- Random messages in each conversation

---

## 📁 Project Structure

### iOS App Architecture

```
┌─────────────────────────────────────────────┐
│              App Layer                      │
│  (messageai_swiftApp.swift)                 │
└─────────────────┬───────────────────────────┘
                  │
    ┌─────────────┼─────────────┐
    │             │             │
┌───▼────┐   ┌───▼─────┐   ┌──▼──────┐
│ Views  │   │ Models  │   │Services │
└────────┘   └─────────┘   └─────────┘
    │             │             │
    ├── Auth      ├── User      ├── AuthService
    ├── Chat      ├── Message   ├── MessagingService
    ├── List      ├── Conv.     ├── FirestoreService
    └── AI        └── AI        └── AIFeaturesService
```

### Key Components

**Services (Observable):**
- `@Observable` classes shared across the app
- Manage state and business logic
- Interface with Firebase SDK

**Models (SwiftData):**
- `@Model` classes for local persistence
- Synchronized with Firestore
- Offline-first architecture

**Views (SwiftUI):**
- Declarative UI components
- Reactive to service state changes
- Environment-based dependency injection

---

## 💻 Development

### Running the App

```bash
# Open in Xcode
open messageai-swift.xcodeproj

# Or use xcodebuild
xcodebuild -scheme messageai-swift -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' build
```

### Developing Functions Locally

```bash
cd functions

# Watch mode for auto-compile
npm run build:watch

# In another terminal, run emulator
firebase emulators:start
```

### Common Development Tasks

**Add a New AI Feature:**

1. Create function in `functions/src/ai/`
2. Export from `functions/src/index.ts`
3. Deploy: `npm run deploy`
4. Add client method in `AIFeaturesService.swift`
5. Create UI in SwiftUI views

**Add a New SwiftData Model:**

1. Define `@Model` class in `Models.swift`
2. Add to model container in app initialization
3. Create Firestore listener in `FirestoreService.swift`
4. Sync data bidirectionally

**Modify Message Schema:**

1. Update `MessageEntity` in `Models.swift`
2. Update Firestore write in `MessagingService.swift`
3. Update listener in `handleMessageSnapshot()`
4. Update mock data in `functions/src/data/mock.ts`

### Debugging

**iOS App:**
- Use Xcode debugger and breakpoints
- Check Console for log output
- Use Instruments for performance profiling

**Firebase Functions:**
```bash
# View logs
firebase functions:log

# View logs for specific function
firebase functions:log --only extractActionItems

# Follow logs in real-time
firebase functions:log --follow
```

**Firestore:**
- Use Firebase Console → Firestore Database
- View real-time updates
- Check security rules

### Monitoring AI Quality

**Telemetry Dashboard:**

View AI performance metrics in Firestore Console under `ai_telemetry` collection:
- **Success Rate**: Count of successful vs failed calls
- **Latency**: Average `durationMs` per function
- **Retry Patterns**: Distribution of `attemptCount` values
- **Error Types**: Group by `errorType` and `errorMessage`

**User Feedback Analysis:**

Review user feedback in Firestore Console under `ai_feedback` collection:
- **Ratings**: Average rating per `featureType`
- **Corrections**: Review `userCorrection` field for accuracy issues
- **Comments**: Read user comments for improvement suggestions

**Cache Performance:**

Monitor cache hit rates in DEBUG logs:
```
[AIFeaturesService] Returning in-memory cached search results
[AIFeaturesService] Returning local search results (12 results)
[AIFeaturesService] Summary for conv-123 expired, returning nil
```

**Example Firestore Queries:**

```javascript
// Get failed AI calls in last 24 hours
db.collection('ai_telemetry')
  .where('success', '==', false)
  .where('timestamp', '>', yesterday)
  .orderBy('timestamp', 'desc')
  .get()

// Get low-rated summaries for review
db.collection('ai_feedback')
  .where('featureType', '==', 'summary')
  .where('rating', '<=', 2)
  .orderBy('timestamp', 'desc')
  .get()
```

---

## 🧪 Testing

### iOS Unit Tests

```bash
# Run all tests
xcodebuild test -scheme messageai-swift -destination 'platform=iOS Simulator,name=iPhone 15'

# Run in Xcode
# Press ⌘ + U
```

### Firebase Functions Tests

```bash
cd functions

# Run tests (if configured)
npm test
```

### Integration Testing with Mock Data

1. **Generate mock data:**
   ```swift
   try await Functions.functions().httpsCallable("generateMockData").call()
   ```

2. **Test AI features:**
   - Extract action items from conversations
   - Check priority classification
   - Test meeting suggestions

3. **Clean up:**
   ```swift
   try await Functions.functions().httpsCallable("deleteConversations").call()
   try await Functions.functions().httpsCallable("deleteUsers").call()
   ```

### Manual Testing Checklist

**Core Features:**
- [ ] User registration and login
- [ ] Create direct conversation
- [ ] Create group conversation
- [ ] Send messages
- [ ] Receive messages
- [ ] Chat with AI bot
- [ ] Extract action items
- [ ] View message priority
- [ ] Suggest meeting times
- [ ] Generate thread summary
- [ ] Track decisions
- [ ] Search conversations

**AI Quality Features:**
- [ ] Verify retry on network failure (airplane mode test)
- [ ] Check cache hit for repeated summary requests
- [ ] Confirm telemetry logged in Firestore `ai_telemetry`
- [ ] Submit AI feedback via thumbs-up button
- [ ] Verify feedback saved in Firestore `ai_feedback`
- [ ] Test cache expiration (summaries expire after 24h)
- [ ] Monitor DEBUG logs for telemetry output

---

## 🚢 Deployment

### Deploy Firebase Functions

```bash
cd functions

# Build TypeScript
npm run build

# Deploy all functions
npm run deploy

# Deploy specific function
firebase deploy --only functions:extractActionItems

# Deploy with specific project
firebase deploy --only functions --project messageai-prod
```

### Deploy iOS App

#### TestFlight (Beta)

1. **Archive the app:**
   - Product → Archive
   - Wait for build to complete

2. **Upload to App Store Connect:**
   - Window → Organizer
   - Select archive → Distribute App
   - Choose App Store Connect
   - Upload

3. **Configure in App Store Connect:**
   - Go to [App Store Connect](https://appstoreconnect.apple.com)
   - Select app → TestFlight
   - Add build to test group
   - Invite testers

#### App Store (Production)

1. Archive and upload (same as TestFlight)
2. In App Store Connect:
   - Create new version
   - Fill in metadata
   - Add screenshots
   - Submit for review

### Environment Configuration

**Development:**
```bash
# .env
OPENAI_API_KEY=sk-dev-key-here
```

**Production:**
```bash
# Set via Firebase Console or CLI
firebase functions:config:set openai.key="sk-prod-key-here"
```

---

## 🐛 Troubleshooting

### Common Issues

#### "GoogleService-Info.plist not found"

**Solution:**
1. Download from Firebase Console
2. Drag into Xcode project
3. Ensure "Copy items if needed" is checked
4. Verify file is in target membership

#### "INTERNAL error" from Firebase Functions

**Check:**
1. Function logs: `firebase functions:log`
2. API keys are set correctly in `.env`
3. Function deployed: `firebase deploy --only functions`

**Common causes:**
- Missing environment variables
- Incorrect request payload
- OpenAI API quota exceeded
- Import errors in TypeScript

#### SwiftData not syncing with Firestore

**Verify:**
1. Firestore listener is started
2. Check listener callbacks are firing
3. Verify SwiftData context is available
4. Check Firestore security rules allow reads

**Debug:**
```swift
// Add logging in FirestoreService
print("[Firestore] Listener fired: \(snapshot.documents.count) docs")
```

#### Messages not sending

**Check:**
1. User is authenticated
2. Firestore security rules allow writes
3. Internet connection active
4. Check MessagingService logs

#### AI Features not working

**Verify:**
1. OpenAI API key is valid
2. Functions are deployed
3. Check function logs for errors
4. Verify request payload format

### Debug Commands

```bash
# Check Firebase project
firebase projects:list

# Check function deployment status
firebase functions:list

# Test function locally
firebase functions:shell

# View Firestore indexes
firebase firestore:indexes

# Check auth users
firebase auth:export users.json
```

### Performance Issues

**iOS App:**
- Use Instruments to profile
- Check SwiftData query performance
- Optimize image loading
- Reduce listener scope

**Firebase Functions:**
- Monitor execution time in Console
- Optimize Firestore queries
- Use batched writes
- Cache AI responses

### Getting Help

1. **Check logs:**
   - Xcode Console for iOS
   - `firebase functions:log` for backend
   - Firebase Console for database

2. **Search issues:**
   - Check GitHub issues
   - Search Stack Overflow

3. **Create issue:**
   - Include error messages
   - Describe steps to reproduce
   - Share relevant code snippets

---

## 🤝 Contributing

### Development Workflow

1. **Create feature branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make changes:**
   - Write code
   - Add tests
   - Update documentation

3. **Commit:**
   ```bash
   git add .
   git commit -m "feat: add your feature"
   ```

4. **Push and create PR:**
   ```bash
   git push origin feature/your-feature-name
   ```

### Code Style

**Swift:**
- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use SwiftLint (if configured)
- 4 spaces for indentation

**TypeScript:**
- Use ESLint (configured in `functions/`)
- 2 spaces for indentation
- Prefer `const` over `let`

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add thread summarization feature
fix: resolve message ordering issue
docs: update README with deployment steps
refactor: extract AI logic into separate service
test: add unit tests for MessagingService
```

---

## 📄 License

[Your License Here]

---

## 🙏 Acknowledgments

- Firebase for backend infrastructure
- OpenAI for AI capabilities
- Apple for SwiftUI framework

---

## 📞 Contact

- **Issues:** [GitHub Issues](your-repo/issues)
- **Email:** [your-email@example.com]
- **Twitter:** [@yourhandle]

---

**Built with ❤️ using Swift, Firebase, and AI**
