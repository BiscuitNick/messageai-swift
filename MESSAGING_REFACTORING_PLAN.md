# MessagingService Refactoring Plan

## Current State
- **File**: MessagingService.swift
- **Lines**: 1614
- **Complexity**: High - handles multiple concerns in one class

## Identified Features

### 1. Conversation Management
- Create conversations (user-to-user, group, bot)
- Find existing conversations (local and remote)
- Cache conversations to SwiftData
- Manage conversation metadata

### 2. Message Sending
- Send messages as user
- Send messages as bot
- Retry failed messages
- Delivery state tracking
- Network simulation support

### 3. Firestore Synchronization
- Observe conversations collection
- Observe messages collections (per conversation)
- Sync Firestore → SwiftData
- Handle snapshot updates
- Manage listeners lifecycle

### 4. Read Status Management
- Mark conversations as read
- Mark messages as read
- Track unread counts per participant
- Update last interaction timestamps

### 5. Bot Integration
- Create bot conversations
- Send bot messages
- Welcome messages
- Bot-specific logic

### 6. Mock Data / Testing
- Seed mock conversations
- Seed mock messages
- Test data generation

## Proposed Architecture

```
MessagingCoordinator
├── Shared Infrastructure
│   ├── FirestoreListener<T> - Generic listener management
│   ├── DeliveryStateTracker - Message delivery tracking
│   └── SwiftDataCache - Generic Firestore → SwiftData sync
└── Feature Services
    ├── ConversationService - Create/find conversations
    ├── MessageSendingService - Send messages, retry logic
    ├── ReadStatusService - Read receipts, unread counts
    ├── BotConversationService - Bot-specific features
    └── FirestoreSyncService - Observe & sync data
```

## Migration Strategy

### Phase 1: Shared Infrastructure
1. `FirestoreListener<T>` - Reusable listener with lifecycle management
2. `DeliveryStateTracker` - Centralized delivery state logic
3. `SwiftDataCache` - Generic sync helper

### Phase 2: Feature Services
1. `ConversationService` - Conversation CRUD
2. `MessageSendingService` - Message sending & retry
3. `ReadStatusService` - Read receipts
4. `BotConversationService` - Bot integration
5. `FirestoreSyncService` - Firestore observers

### Phase 3: Coordinator
1. `MessagingCoordinator` - Compose services
2. Wire dependencies
3. Provide unified API

### Phase 4: Migration
1. Update app initialization
2. Update views
3. Remove old MessagingService
4. Build & test

## Benefits

- **Separation of Concerns**: Each service has single responsibility
- **Testability**: Services can be tested independently
- **Reusability**: Shared infrastructure reduces duplication
- **Maintainability**: Smaller, focused files
- **Scalability**: Easy to add new features

## Estimated Impact

- **Files Created**: ~12 (5 infrastructure + 5 services + 1 coordinator + 1 doc)
- **Average File Size**: ~150-200 lines
- **Code Reduction**: ~200 lines (eliminating duplication)
- **Migration Time**: 3-4 hours
