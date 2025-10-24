# MessageAI MVP - Product Requirements Document

## Project Overview

**Timeline**: 24 hours (MVP hard gate)  
**Stack**: Swift (iOS) + Firebase  
**Goal**: Build production-quality messaging infrastructure with real-time sync and offline support

## MVP Success Criteria

The MVP is a hard gate. All features below must be fully functional:

### Core Messaging Features
1. **One-on-one chat functionality**
2. **Real-time message delivery** between 2+ users
3. **Message persistence** (survives app restarts)
4. **Optimistic UI updates** (messages appear instantly before server confirmation)
5. **Online/offline status indicators**
6. **Message timestamps**
7. **User authentication** (users have accounts/profiles)
8. **Basic group chat functionality** (3+ users in one conversation)
9. **Message read receipts**
10. **Push notifications** (at least in foreground)

### Deployment Requirement
- Running on local emulator/simulator with deployed backend
- TestFlight deployment preferred but not required for MVP

## Technical Architecture

### Frontend (iOS - Swift)
- **Framework**: SwiftUI
- **Local Storage**: SwiftData (for message persistence)
- **Networking**: Firebase SDK
- **State Management**: SwiftUI @Observable pattern
- **Minimum iOS Version**: iOS 17.0

### Backend (Firebase)
- **Database**: Firebase Firestore (real-time sync)
- **Authentication**: Firebase Auth (email/password minimum)
- **Push Notifications**: Firebase Cloud Messaging (FCM)
- **Storage**: Firebase Storage (for profile pictures)
- **Hosting**: Firebase Hosting (optional for web dashboard)

## Detailed Feature Requirements

### 1. User Authentication
**Must Have**:
- Email/password sign up and login
- User profile creation (display name, profile picture)
- Persistent authentication state
- Logout functionality

**Data Model**:
```swift
User {
  id: String
  email: String
  displayName: String
  profilePictureURL: String?
  isOnline: Bool
  lastSeen: Date
  createdAt: Date
}
```

### 2. One-on-One Chat
**Must Have**:
- Create new conversation with any user
- Send text messages
- View conversation history
- Real-time message updates
- Message delivery states: sending → sent → delivered → read

**Data Model**:
```swift
Conversation {
  id: String
  participantIds: [String]
  lastMessage: String?
  lastMessageTimestamp: Date?
  unreadCount: [String: Int] // userId: count
  createdAt: Date
}

Message {
  id: String
  conversationId: String
  senderId: String
  text: String
  timestamp: Date
  deliveryStatus: DeliveryStatus // sending, sent, delivered, read
  readBy: [String] // userIds who read the message
}
```

### 3. Real-Time Message Delivery
**Must Have**:
- Firestore real-time listeners for instant message delivery
- Messages appear on recipient device within 1 second (on good network)
- Typing indicators (show when other user is typing)
- Online/offline presence updates

**Technical Implementation**:
- Use Firestore `addSnapshotListener` for real-time updates
- Update user's `isOnline` status on app lifecycle changes
- Use Firestore presence system with `onDisconnect()` triggers

### 4. Message Persistence & Offline Support
**Must Have**:
- All messages stored locally using SwiftData
- App works offline (can view message history)
- Messages queue when offline and send when online
- No message loss on app crash or force quit

**Technical Implementation**:
- SwiftData models mirror Firestore structure
- Sync strategy: Firestore → SwiftData on receive, SwiftData → Firestore on send
- Use Firestore offline persistence: `Firestore.firestore().settings.isPersistenceEnabled = true`
- Queue failed sends with retry logic

### 5. Optimistic UI Updates
**Must Have**:
- Message appears instantly in sender's UI
- Show "sending" state with loading indicator
- Update to "sent" when Firestore write confirms
- Update to "delivered" when recipient receives
- Update to "read" when recipient opens conversation

**Technical Implementation**:
- Add message to local SwiftData immediately
- Assign temporary ID, replace with Firestore ID on confirmation
- Update delivery status through Firestore listeners

### 6. Group Chat
**Must Have**:
- Create group with 3+ users
- Group name and optional group picture
- All members see all messages in real-time
- Message attribution (show sender name/picture)
- Read receipts show who read each message

**Data Model**:
```swift
Conversation {
  // ... existing fields
  isGroup: Bool
  groupName: String?
  groupPictureURL: String?
  adminIds: [String]
}
```

### 7. Read Receipts
**Must Have**:
- Mark messages as read when conversation is opened
- Show read status on sender's side
- In groups, show count of users who read message
- Visual indicator: checkmarks (sent ✓, delivered ✓✓, read ✓✓ blue)

### 8. Push Notifications
**Must Have**:
- Foreground notifications (minimum requirement)
- Show sender name and message preview
- Tap notification opens conversation
- Badge count for unread messages

**Nice to Have** (if time permits):
- Background notifications
- Notification grouping by conversation

### 9. Message Timestamps
**Must Have**:
- Show timestamp for each message
- Group messages by date (Today, Yesterday, specific dates)
- Relative timestamps (Just now, 5m ago, etc.)
- Full timestamp on long-press

### 10. Online/Offline Status
**Must Have**:
- Green dot indicator when user is online
- "Last seen" timestamp when offline
- Update presence in real-time
- Handle app backgrounding correctly

## User Interface Requirements

### Screens (Minimum)
1. **Authentication Screen**
   - Login form
   - Sign up form
   - Password reset (optional)

2. **Conversations List**
   - List of all conversations (1-on-1 and groups)
   - Show last message preview
   - Unread count badge
   - Online status indicator
   - Pull to refresh
   - Swipe to delete (optional)

3. **Chat Screen**
   - Message list (scrollable, reverse chronological)
   - Text input field
   - Send button
   - Typing indicator
   - Message delivery status indicators
   - Timestamps
   - Profile picture for each message
   - Navigation bar with conversation name/participants

4. **New Conversation Screen**
   - Search/select users
   - Create 1-on-1 or group chat
   - Set group name (for groups)

5. **Profile Screen** (optional for MVP)
   - Edit display name
   - Change profile picture
   - Logout button

### Design Guidelines
- Clean, modern UI similar to WhatsApp/iMessage
- System fonts and native iOS components
- Light mode (dark mode optional)
- Smooth animations and transitions
- Loading states for all async operations
- Error handling with user-friendly messages

## Testing Requirements

### Critical Test Scenarios
1. **Two devices chatting in real-time**
   - Send messages back and forth
   - Verify instant delivery
   - Check read receipts

2. **Offline scenario**
   - Turn off WiFi/cellular on one device
   - Send messages to offline device
   - Verify messages queue
   - Turn network back on
   - Verify messages deliver

3. **App lifecycle**
   - Send message while app is backgrounded
   - Force quit app mid-send
   - Reopen and verify message sent
   - Verify message history persists

4. **Poor network conditions**
   - Enable airplane mode
   - Send messages (should queue)
   - Disable airplane mode
   - Verify messages send

5. **Rapid-fire messages**
   - Send 20+ messages quickly
   - Verify all messages deliver in order
   - Check for race conditions

6. **Group chat**
   - Create group with 3+ users
   - Send messages from different users
   - Verify all users receive all messages
   - Check read receipts

## Firebase Setup Requirements

### Firestore Collections Structure
```
users/
  {userId}/
    - email, displayName, profilePictureURL, isOnline, lastSeen

conversations/
  {conversationId}/
    - participantIds, isGroup, groupName, lastMessage, lastMessageTimestamp
    
    messages/
      {messageId}/
        - senderId, text, timestamp, deliveryStatus, readBy

presence/
  {userId}/
    - isOnline, lastSeen, connections
```

### Security Rules
- Users can only read/write their own user document
- Users can only read conversations they're part of
- Users can only send messages to conversations they're in
- Read receipts can only be updated by the reading user

### Indexes Required
- `conversations` collection: `participantIds` array-contains + `lastMessageTimestamp` desc
- `messages` subcollection: `timestamp` asc

### Cloud Functions (Optional for MVP)
- Update conversation's `lastMessage` and `lastMessageTimestamp` on new message
- Send push notifications on new message
- Clean up presence on user disconnect

## Performance Requirements

- **Message delivery**: < 1 second on good network
- **App launch**: < 2 seconds to show conversations list
- **Conversation load**: < 1 second to show last 50 messages
- **Scroll performance**: 60 FPS when scrolling messages
- **Offline mode**: Instant access to cached messages

## Out of Scope (Post-MVP)

The following features are NOT required for MVP:
- AI features (thread summarization, translation, etc.)
- Media messages (images, videos, audio)
- Voice/video calls
- Message editing or deletion
- Message reactions (emoji reactions)
- Message forwarding
- Search functionality
- Message encryption (beyond Firebase's default)
- Custom notification sounds
- Delivery reports/analytics
- User blocking
- Message pinning
- Conversation archiving
- TestFlight deployment (preferred but not required)

## Success Metrics

MVP is successful if:
1. ✅ All 10 core features are functional
2. ✅ Messages sync reliably between devices
3. ✅ App handles offline/online transitions gracefully
4. ✅ No message loss in any test scenario
5. ✅ App performs well on physical iOS device
6. ✅ Code is clean and maintainable for future AI features

## Development Timeline (24 Hours)

**Hours 0-4: Foundation**
- Firebase project setup
- Xcode project configuration
- SwiftData models
- Firebase Auth integration

**Hours 4-10: Core Messaging**
- Firestore structure implementation
- Message sending/receiving
- Real-time listeners
- Local persistence

**Hours 10-16: UI & Features**
- Conversations list UI
- Chat screen UI
- Optimistic updates
- Read receipts
- Typing indicators

**Hours 16-20: Group Chat & Polish**
- Group chat functionality
- Online/offline presence
- Push notifications (foreground)
- Bug fixes

**Hours 20-24: Testing & Deployment**
- Test all scenarios
- Fix critical bugs
- Deploy Firebase backend
- Test on physical device

## Technical Decisions

### Why SwiftUI?
- Fastest development for iOS
- Modern, declarative UI
- Built-in state management
- Native performance

### Why SwiftData?
- Native iOS persistence
- Type-safe Swift models
- Automatic iCloud sync (future feature)
- Better than Core Data for new projects

### Why Firestore?
- Real-time sync out of the box
- Offline persistence built-in
- Scalable to millions of users
- Simple security rules

### Why Not Build Custom Backend?
- Time constraint (24 hours)
- Firebase handles real-time sync better
- Less infrastructure to manage
- Focus on app features, not DevOps

## Risk Mitigation

### Potential Blockers
1. **Firestore real-time sync issues**
   - Mitigation: Use Firebase offline persistence, test early

2. **Push notifications not working**
   - Mitigation: Foreground notifications only for MVP, background is nice-to-have

3. **SwiftData sync bugs**
   - Mitigation: Keep models simple, test persistence early

4. **Group chat complexity**
   - Mitigation: Start with 1-on-1, add groups at hour 16

5. **Time management**
   - Mitigation: Focus on core messaging first, polish later

## Next Steps After MVP

Once MVP is approved:
1. Choose user persona (Remote Team, International, Parent, or Creator)
2. Implement 5 required AI features for chosen persona
3. Implement 1 advanced AI capability
4. Add media support (images minimum)
5. Deploy to TestFlight
6. Record demo video
7. Write persona brainlift document

---

**Remember**: A simple, reliable messaging app beats a feature-rich app with flaky message delivery. Focus on making messages sync perfectly before adding any extras.
