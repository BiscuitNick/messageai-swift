# MessageAI MVP - Development Tasks

## Overview
**Timeline**: 24 hours (MVP hard gate)  
**Stack**: Swift (iOS) + Firebase  
**Goal**: Build production-quality messaging infrastructure with real-time sync and offline support

---

## Phase 1: Foundation (Hours 0-4)

### Task 1.1: Firebase Project Setup
**Duration**: 1 hour  
**Priority**: Critical

#### Subtasks:
- [x] Create Firebase project in Firebase Console
- [x] Enable Authentication (Email/Password)
- [x] Enable Firestore Database
- [ ] Enable Cloud Messaging (FCM)
- [x] Enable Storage (for profile pictures)
- [x] Download GoogleService-Info.plist
- [ ] Configure Firestore security rules (basic structure)
- [ ] Set up Firestore indexes for conversations and messages
- [x] Test Firebase connection from iOS app

### Task 1.2: Xcode Project Configuration
**Duration**: 1 hour  
**Priority**: Critical

#### Subtasks:
- [x] Add Firebase SDK via Swift Package Manager
- [x] Add GoogleService-Info.plist to Xcode project
- [x] Configure Firebase in App file
- [x] Set minimum iOS deployment target to 17.0
- [x] Configure app capabilities (Push Notifications, Background Modes)
- [x] Set up proper bundle identifier and signing
- [x] Test Firebase initialization

### Task 1.3: SwiftData Models
**Duration**: 1.5 hours  
**Priority**: Critical

#### Subtasks:
- [x] Create User model with @Model
  - [x] id: String
  - [x] email: String
  - [x] displayName: String
  - [x] profilePictureURL: String?
  - [x] isOnline: Bool
  - [x] lastSeen: Date
  - [x] createdAt: Date
- [x] Create Conversation model with @Model
  - [x] id: String
  - [x] participantIds: [String]
  - [x] isGroup: Bool
  - [x] groupName: String?
  - [x] groupPictureURL: String?
  - [x] adminIds: [String]
  - [x] lastMessage: String?
  - [x] lastMessageTimestamp: Date?
  - [x] unreadCount: [String: Int]
  - [x] createdAt: Date
- [x] Create Message model with @Model
  - [x] id: String
  - [x] conversationId: String
  - [x] senderId: String
  - [x] text: String
  - [x] timestamp: Date
  - [x] deliveryStatus: DeliveryStatus enum
  - [x] readBy: [String]
- [x] Create DeliveryStatus enum (sending, sent, delivered, read)
- [x] Configure SwiftData container in App file
- [x] Test model creation and persistence

### Task 1.4: Firebase Auth Integration
**Duration**: 0.5 hours  
**Priority**: Critical

#### Subtasks:
- [x] Create AuthService class with @Observable
- [x] Implement signUp(email, password, displayName)
- [x] Implement signIn(email, password)
- [x] Implement signOut()
- [x] Implement getCurrentUser()
- [x] Add auth state listener
- [x] Handle auth errors with user-friendly messages
- [ ] Test authentication flow (multi-device)

---

## Phase 2: Core Messaging (Hours 4-10)

### Task 2.1: Firestore Structure Implementation
**Duration**: 1.5 hours  
**Priority**: Critical

#### Subtasks:
- [x] Create FirestoreService class with @Observable
- [x] Implement user document creation/update
- [x] Implement conversation document creation
- [x] Implement message subcollection structure
- [ ] Add Firestore security rules for users collection
- [ ] Add Firestore security rules for conversations collection
- [ ] Add Firestore security rules for messages subcollection
- [ ] Test Firestore read/write operations (instrumented)

### Task 2.2: Message Sending/Receiving
**Duration**: 2 hours  
**Priority**: Critical

#### Subtasks:
- [x] Implement sendMessage(conversationId, text) function
- [x] Add message to local SwiftData immediately (optimistic update)
- [x] Write message to Firestore messages subcollection
- [x] Handle send failures with retry logic
- [ ] Update message delivery status on success (delivered/read propagation)
- [x] Implement receiveMessage listener for real-time updates
- [x] Sync received messages to local SwiftData
- [ ] Test message sending between two devices

### Task 2.3: Real-Time Listeners
**Duration**: 1.5 hours  
**Priority**: Critical

#### Subtasks:
- [x] Implement conversation listener (for conversation list updates)
- [x] Implement messages listener (for real-time message updates)
- [x] Implement user presence listener (for online/offline status)
- [ ] Add typing indicator listener
- [x] Handle listener cleanup on view disappear
- [ ] Implement offline/online detection
- [x] Update user presence on app lifecycle changes
- [ ] Test real-time updates (multi-session)

### Task 2.4: Local Persistence
**Duration**: 1 hour  
**Priority**: Critical

#### Subtasks:
- [x] Implement sync from Firestore to SwiftData
- [x] Implement sync from SwiftData to Firestore
- [ ] Add offline message queuing
- [ ] Implement message retry on network restore
- [ ] Add data migration handling
- [ ] Test offline/online message persistence
- [ ] Verify no message loss on app restart

---

## Phase 3: UI & Features (Hours 10-16)

### Task 3.1: Conversations List UI
**Duration**: 2 hours  
**Priority**: High

#### Subtasks:
- [x] Create ConversationsListView with SwiftUI
- [x] Implement conversation list with ForEach
- [x] Add last message preview display
- [x] Add unread count badge
- [ ] Add online status indicator (green dot)
- [ ] Add search / pull-to-refresh functionality
- [x] Add navigation to chat screen
- [ ] Add swipe-to-delete (optional)
- [ ] Style with modern UI (WhatsApp/iMessage-like)
- [ ] Add loading states and error handling

### Task 3.2: Chat Screen UI
**Duration**: 2.5 hours  
**Priority**: High

#### Subtasks:
- [x] Create ChatView with SwiftUI
- [x] Implement message list with ScrollViewReader
- [x] Add message bubble styling (sent vs received)
- [ ] Add profile picture for each message
- [x] Add message timestamps
- [ ] Add delivery status indicators (checkmarks)
- [x] Implement text input field with send button
- [x] Add auto-scroll to bottom on new messages
- [ ] Add message grouping by date
- [ ] Style with modern chat UI

### Task 3.3: Optimistic Updates
**Duration**: 1 hour  
**Priority**: High

#### Subtasks:
- [x] Show "sending" state with loading indicator
- [x] Update to "sent" when Firestore confirms
- [ ] Update to "delivered" when recipient receives
- [x] Update to "read" when recipient opens conversation
- [x] Handle temporary message IDs
- [ ] Replace temp ID with Firestore ID on confirmation
- [x] Add error state for failed sends
- [ ] Test optimistic updates flow

### Task 3.4: Read Receipts
**Duration**: 1 hour  
**Priority**: High

#### Subtasks:
- [ ] Mark messages as read when conversation opens
- [ ] Update readBy array in Firestore
- [ ] Show read status on sender's side
- [ ] Add visual indicators (✓, ✓✓, ✓✓ blue)
- [ ] Handle group read receipts (count display)
- [ ] Update read status in real-time
- [ ] Test read receipts between devices

### Task 3.5: Typing Indicators
**Duration**: 0.5 hours  
**Priority**: Medium

#### Subtasks:
- [ ] Add typing indicator to chat UI
- [ ] Implement typing status updates to Firestore
- [ ] Add typing listener for real-time updates
- [ ] Show "User is typing..." message
- [ ] Add timeout for typing indicator (3 seconds)
- [ ] Test typing indicators between devices

---

## Phase 4: Group Chat & Polish (Hours 16-20)

### Task 4.1: Group Chat Functionality
**Duration**: 2 hours  
**Priority**: High

#### Subtasks:
- [ ] Create NewConversationView for group creation
- [ ] Add user search/selection functionality
- [ ] Implement group creation with 3+ users
- [ ] Add group name input field
- [ ] Update conversation model for groups
- [ ] Add group picture selection (optional)
- [ ] Implement group admin functionality
- [ ] Add group member management
- [ ] Test group chat with 3+ participants

### Task 4.2: Online/Offline Presence
**Duration**: 1 hour  
**Priority**: High

#### Subtasks:
- [ ] Implement user presence tracking
- [ ] Add "Last seen" timestamp display
- [ ] Update presence on app background/foreground
- [ ] Add presence indicators in conversation list
- [ ] Add presence indicators in chat screen
- [ ] Handle presence cleanup on disconnect
- [ ] Test presence updates in real-time

### Task 4.3: Push Notifications (Foreground)
**Duration**: 1 hour  
**Priority**: High

#### Subtasks:
- [x] Configure FCM in iOS app
- [x] Request notification permissions
- [x] Implement foreground notification handling
- [ ] Add notification tap to open conversation
- [ ] Implement badge count for unread messages
- [ ] Add sender name and message preview
- [ ] Test notifications between devices
- [ ] Handle notification when app is active

### Task 4.4: Bug Fixes & Polish
**Duration**: 1 hour  
**Priority**: Medium

#### Subtasks:
- [ ] Fix any UI layout issues
- [ ] Improve error handling and user feedback
- [ ] Add loading states for all async operations
- [ ] Optimize scroll performance
- [ ] Fix any memory leaks
- [ ] Improve app responsiveness
- [ ] Add proper error messages
- [ ] Test edge cases and error scenarios

---

## Phase 5: Testing & Deployment (Hours 20-24)

### Task 5.1: Critical Test Scenarios
**Duration**: 2 hours  
**Priority**: Critical

#### Subtasks:
- [ ] Test two devices chatting in real-time
  - [ ] Send messages back and forth
  - [ ] Verify instant delivery
  - [ ] Check read receipts
- [ ] Test offline scenario
  - [ ] Turn off WiFi/cellular on one device
  - [ ] Send messages to offline device
  - [ ] Verify messages queue
  - [ ] Turn network back on
  - [ ] Verify messages deliver
- [ ] Test app lifecycle
  - [ ] Send message while app is backgrounded
  - [ ] Force quit app mid-send
  - [ ] Reopen and verify message sent
  - [ ] Verify message history persists
- [ ] Test poor network conditions
  - [ ] Enable airplane mode
  - [ ] Send messages (should queue)
  - [ ] Disable airplane mode
  - [ ] Verify messages send
- [ ] Test rapid-fire messages
  - [ ] Send 20+ messages quickly
  - [ ] Verify all messages deliver in order
  - [ ] Check for race conditions
- [ ] Test group chat
  - [ ] Create group with 3+ users
  - [ ] Send messages from different users
  - [ ] Verify all users receive all messages
  - [ ] Check read receipts

### Task 5.2: Performance Optimization
**Duration**: 1 hour  
**Priority**: Medium

#### Subtasks:
- [ ] Optimize message loading (pagination)
- [ ] Improve scroll performance (60 FPS)
- [ ] Optimize image loading and caching
- [ ] Reduce memory usage
- [ ] Optimize Firestore queries
- [ ] Add proper error boundaries
- [ ] Test on older iOS devices
- [ ] Measure and improve app launch time

### Task 5.3: Firebase Backend Deployment
**Duration**: 0.5 hours  
**Priority**: High

#### Subtasks:
- [ ] Deploy Firestore security rules
- [ ] Deploy Firestore indexes
- [ ] Configure FCM for production
- [ ] Test production Firebase setup
- [ ] Verify all features work with production backend
- [ ] Document Firebase configuration

### Task 5.4: Physical Device Testing
**Duration**: 0.5 hours  
**Priority**: Critical

#### Subtasks:
- [ ] Install app on physical iOS device
- [ ] Test all features on real device
- [ ] Verify performance on actual hardware
- [ ] Test push notifications on device
- [ ] Test offline/online scenarios
- [ ] Verify app lifecycle handling
- [ ] Test with poor network conditions
- [ ] Document any device-specific issues

---

## Success Criteria Checklist

### Core Messaging Features (All Required)
- [ ] ✅ One-on-one chat functionality
- [ ] ✅ Real-time message delivery between 2+ users
- [ ] ✅ Message persistence (survives app restarts)
- [ ] ✅ Optimistic UI updates (messages appear instantly)
- [ ] ✅ Online/offline status indicators
- [ ] ✅ Message timestamps
- [ ] ✅ User authentication (users have accounts/profiles)
- [ ] ✅ Basic group chat functionality (3+ users)
- [ ] ✅ Message read receipts
- [ ] ✅ Push notifications (at least in foreground)

### Technical Requirements
- [ ] ✅ Messages sync reliably between devices
- [ ] ✅ App handles offline/online transitions gracefully
- [ ] ✅ No message loss in any test scenario
- [ ] ✅ App performs well on physical iOS device
- [ ] ✅ Code is clean and maintainable for future AI features

---

## Current Focus & Next Steps

1. **Lock down Firebase backend**
   - Author security rules + indexes
   - Turn on / validate foreground FCM alerts

2. **Realtime polish**
   - Propagate delivered/read states back to senders (replace temp IDs)
   - Surface presence + typing indicators in the UI

3. **Offline resilience**
   - Queue unsent messages, retry on reconnect
   - Stress tests: airplane mode, force quit mid-send
   - Persist failed sends with exponential backoff
   - Surface send errors with retry button

4. **UI enhancements**
   - Presence dot & search/pull-to-refresh in conversation list
   - Chat bubble avatars, grouped timestamps, delivery icons

5. **Multi-device QA**
   - Two-device chat, group scenario, notification flow
   - Physical device run + performance/profile pass
   - Foreground push alert verification (FCM token, APNs sandbox)

---

## Risk Mitigation Tasks

### High Priority Risks
- [ ] **Firestore real-time sync issues**
  - [ ] Test real-time listeners early and often
  - [ ] Implement proper error handling for sync failures
  - [ ] Use Firebase offline persistence
- [ ] **Push notifications not working**
  - [ ] Focus on foreground notifications only for MVP
  - [ ] Test FCM configuration thoroughly
  - [ ] Have fallback notification strategy
- [ ] **SwiftData sync bugs**
  - [ ] Keep models simple and test persistence early
  - [ ] Implement proper data migration
  - [ ] Test offline/online data sync thoroughly
- [ ] **Group chat complexity**
  - [ ] Start with 1-on-1 chat first
  - [ ] Add group functionality incrementally
  - [ ] Test group features thoroughly
- [ ] **Time management**
  - [ ] Focus on core messaging first
  - [ ] Polish features later
  - [ ] Have MVP feature prioritization ready

---

## Notes

- **Focus on core messaging first** - A simple, reliable messaging app beats a feature-rich app with flaky message delivery
- **Test early and often** - Use physical devices for testing, not just simulators
- **Keep it simple** - Don't over-engineer features that aren't required for MVP
- **Document issues** - Keep track of bugs and solutions for future reference
- **Prepare for AI features** - Structure code to easily add AI features post-MVP

---

**Remember**: The MVP is a hard gate. All 10 core features must be fully functional to pass the checkpoint. Focus on making messages sync perfectly before adding any extras.
