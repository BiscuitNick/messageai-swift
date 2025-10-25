# Feature PRD: Testing Infrastructure & Message Delivery Improvements

## Project Context
**Project**: MessageAI - iOS Messaging App  
**Focus Areas**: Developer Experience, Message Delivery UX, Code Organization

---

## Features Overview

1. **Enhanced Debug View** - Improved testing tools and network simulation
2. **Message Delivery States** - Accurate message status tracking with read receipts
3. **Typing Indicators** - Real-time typing bubbles for user-to-user chats
4. **Code Refactoring** - Organized file structure and maintainability

---

## 1. Enhanced Debug View

### Requirements

#### Database Tools Section
- Show separator line ONLY if tool was used in current session
- Display timestamp of last usage below tool name
- Track tool usage in memory with optional UserDefaults persistence

#### Connectivity Section
**Controls**:
1. **WiFi Toggle** - ON/OFF switch for airplane mode simulation
2. **Network Quality Selector**:
   - Normal (no delay)
   - Poor (500-1000ms latency, 10% packet loss)
   - Very Poor (1500-3000ms latency, 25% packet loss)
   - Offline (complete disconnection)
3. **Status Indicator** - Green/Yellow/Red dot showing connection state

**Integration**:
- Wrap Firebase operations with network simulator
- Apply latency and packet loss to operations
- Persist settings across debug sessions

---

## 2. Message Delivery States

### Data Model

```
/conversations/{conversationId}/messages/{messageId}
{
  text: "Hey there!",
  senderId: "userA",
  timestamp: <serverTimestamp>,
  readBy: {
    "userB": <timestamp>,
    "userC": <timestamp>
  },
  deliveryState: "sent" // pending, sent, failed
}
```

### Message States

```swift
enum MessageDeliveryState {
    case pending    // Sending to server
    case sent       // Server confirmed receipt
    case delivered  // At least one recipient received
    case read       // At least one recipient read
    case failed     // Send failed
}
```

### Visual Indicators
- **Pending**: Single gray checkmark (animated)
- **Sent**: Single blue checkmark
- **Delivered**: Double blue checkmark
- **Read**: Double blue checkmark (bold)
- **Failed**: Red exclamation with retry option

### State Transition Logic
1. User sends → `.pending` (optimistic UI)
2. Firebase confirms write → `.sent`
3. Any recipient in conversation → `.delivered`
4. Check `readBy` map:
   - Empty or only sender → `.sent`
   - Contains other users → `.read`

### Read Receipt Implementation
- **Writing**: When user opens conversation, update all unread messages:
  ```swift
  readBy[currentUserId] = FieldValue.serverTimestamp()
  ```
- **Reading**: Query messages where `readBy` doesn't contain current user ID
- **Display**: Show read status based on `readBy` map size/contents
- **Group chats**: Display count of readers or specific users who read

---

## 3. Typing Indicators for User Chats

### Data Model
```
/conversations/{conversationId}/typingStatus/{userId}
{
  isTyping: true,
  lastUpdated: <timestamp>,
  expiresAt: <timestamp + 5s>
}
```

### Behavior
- Broadcast typing state to Firestore on text input
- Auto-clear after 5 seconds of inactivity
- Listen for other users' typing status
- Show typing bubble below messages
- Support multiple users typing simultaneously

### UI Components
- Animated typing bubble with 3 dots
- User name label for group chats
- Position at bottom of message list
- Smooth fade in/out animations

---

## 4. Code Refactoring

### File Organization

**Services**:
```
Services/
├─ Messaging/
│  ├─ MessageService.swift
│  ├─ MessageSender.swift
│  ├─ MessageListener.swift
│  ├─ ReadReceiptService.swift
│  └─ TypingStatusService.swift
├─ AI/
│  ├─ AIFeaturesService.swift
│  ├─ AIAgentService.swift
│  └─ OpenAIClient.swift
├─ Firebase/
│  ├─ FirebaseAuthService.swift
│  ├─ FirestoreService.swift
│  └─ FirebaseStorageService.swift
└─ Network/
   ├─ NetworkMonitor.swift
   └─ NetworkSimulator.swift
```

**Models**:
```
Models/
├─ Message/
│  ├─ Message.swift
│  ├─ MessageDeliveryState.swift
│  └─ MessageExtensions.swift
├─ Conversation/
│  ├─ Conversation.swift
│  ├─ ConversationMetadata.swift
│  └─ TypingStatus.swift
└─ User/
   ├─ User.swift
   └─ UserProfile.swift
```

**Views**:
```
Views/
├─ Conversations/
│  ├─ ConversationListView.swift
│  └─ NewConversationView.swift
├─ Messages/
│  ├─ MessageListView.swift
│  ├─ MessageBubbleView.swift
│  ├─ MessageInputView.swift
│  └─ TypingIndicatorView.swift
└─ Debug/
   ├─ DebugMenuView.swift
   ├─ ConnectivityTestView.swift
   └─ DatabaseToolsView.swift
```

### Code Quality Guidelines
- Maximum 300 lines per file
- Single responsibility per file/class
- Clear naming conventions
- Consistent folder structure

---

## Success Criteria

### Enhanced Debug View
- ✅ Only used tools show separator lines
- ✅ Network conditions can be toggled without app restart
- ✅ Connectivity status accurately reflects simulation

### Message Delivery States
- ✅ Messages show "pending" until server confirms
- ✅ Read receipts update atomically per message
- ✅ Failed messages show retry option
- ✅ Group chats show read count or user list
- ✅ No race conditions in read status updates

### Typing Indicators
- ✅ Typing status broadcasts in real-time
- ✅ Indicators auto-clear after 5 seconds
- ✅ Works in both 1-on-1 and group chats
- ✅ Smooth animations and transitions

### Code Refactoring
- ✅ No files exceed 300 lines
- ✅ Related functionality grouped in folders
- ✅ Services properly separated by domain
- ✅ Views organized by feature area

---

## Technical Notes

### Read Receipts Advantages
- **Atomic updates**: Each message tracks its own read status
- **Scalable**: Works for any group size
- **Granular**: Individual message-level receipts
- **Efficient queries**: Can query unread messages directly
- **Historical**: Preserves when each user read each message

### Performance Considerations
- Batch `readBy` updates when marking multiple messages as read
- Index on `readBy` field for efficient unread queries
- Minimize Firestore writes for typing status
- Implement proper cleanup of listeners

### Firebase Security Rules
```javascript
// Only allow users to add themselves to readBy
match /conversations/{convId}/messages/{msgId} {
  allow update: if request.auth.uid in resource.data.participantIds
    && request.resource.data.diff(resource.data)
       .affectedKeys().hasOnly(['readBy'])
    && request.auth.uid in request.resource.data.readBy;
}
```