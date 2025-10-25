# AIFeaturesService Refactoring Migration Guide

## Overview

The monolithic `AIFeaturesService` (2368 lines) has been refactored into a composition of focused, single-responsibility services coordinated by `AIFeaturesCoordinator`.

## Architecture Changes

### Before: Monolithic Service
```
AIFeaturesService (2368 lines)
├── Thread Summarization
├── Action Item Extraction
├── Decision Tracking
├── Semantic Search
├── Meeting Suggestions
├── Scheduling Intent Detection
├── Coordination Insights
├── Proactive Alerts
└── Shared infrastructure (retry logic, caching, telemetry)
```

### After: Modular Architecture
```
AIFeaturesCoordinator
├── Shared Infrastructure
│   ├── FirebaseFunctionClient (retry logic + error handling)
│   ├── TelemetryLogger (telemetry handling)
│   ├── CacheManager<T> (generic caching)
│   └── FeatureState<T> (generic state management)
└── Feature Services
    ├── SummaryService
    ├── ActionItemsService
    ├── SearchService
    ├── MeetingSuggestionsService
    ├── SchedulingService
    ├── DecisionTrackingService
    └── CoordinationInsightsService
```

## New File Structure

```
messageai-swift/Services/AI/
├── AIFeaturesCoordinator.swift          # Main coordinator (replaces AIFeaturesService)
├── Shared/                              # Shared infrastructure
│   ├── CacheManager.swift               # Generic cache with expiration
│   ├── FeatureState.swift               # Generic state container
│   ├── TelemetryLogger.swift            # Telemetry logging
│   └── FirebaseFunctionClient.swift    # Firebase calls with retry
└── Features/                            # Individual feature services
    ├── SummaryService.swift
    ├── ActionItemsService.swift
    ├── SearchService.swift
    ├── MeetingSuggestionsService.swift
    ├── SchedulingService.swift
    ├── DecisionTrackingService.swift
    └── CoordinationInsightsService.swift
```

## Migration Steps

### Step 1: Replace Service Initialization

**Before:**
```swift
let aiService = AIFeaturesService()
```

**After:**
```swift
let aiCoordinator = AIFeaturesCoordinator()
```

### Step 2: Update Configuration

**Before:**
```swift
aiService.configure(
    modelContext: modelContext,
    authService: authService,
    messagingService: messagingService,
    firestoreService: firestoreService,
    networkMonitor: networkMonitor
)
```

**After:**
```swift
aiCoordinator.configure(
    modelContext: modelContext,
    authService: authService,
    messagingService: messagingService,
    firestoreService: firestoreService,
    networkMonitor: networkMonitor
)
```

### Step 3: Update Function Calls

**Before:**
```swift
// Thread summarization
let summary = try await aiService.summarizeThreadTask(
    conversationId: conversationId,
    messageLimit: 50,
    saveLocally: true,
    forceRefresh: false
)

// Action items
let actionItems = try await aiService.extractActionItems(
    conversationId: conversationId,
    windowDays: 7,
    forceRefresh: false
)

// Search
let results = try await aiService.smartSearch(
    query: query,
    maxResults: 20,
    forceRefresh: false
)

// Meeting suggestions
let suggestions = try await aiService.suggestMeetingTimes(
    conversationId: conversationId,
    participantIds: participantIds,
    durationMinutes: 60,
    preferredDays: 14,
    forceRefresh: false
)

// Decisions
let decisions = try await aiService.recordDecisions(
    conversationId: conversationId,
    windowDays: 30
)
```

**After:**
```swift
// Thread summarization
let summary = try await aiCoordinator.summaryService.summarizeThread(
    conversationId: conversationId,
    messageLimit: 50,
    saveLocally: true,
    forceRefresh: false
)

// Action items
let actionItems = try await aiCoordinator.actionItemsService.extractActionItems(
    conversationId: conversationId,
    windowDays: 7,
    forceRefresh: false
)

// Search
let results = try await aiCoordinator.searchService.search(
    query: query,
    maxResults: 20,
    forceRefresh: false
)

// Meeting suggestions
let suggestions = try await aiCoordinator.meetingSuggestionsService.suggestMeetingTimes(
    conversationId: conversationId,
    participantIds: participantIds,
    durationMinutes: 60,
    preferredDays: 14,
    forceRefresh: false
)

// Decisions
let decisions = try await aiCoordinator.decisionTrackingService.recordDecisions(
    conversationId: conversationId,
    windowDays: 30
)
```

### Step 4: Update State Observations

**Before:**
```swift
// Per-conversation states
if aiService.summaryLoadingStates[conversationId] == true {
    ProgressView()
}

if let error = aiService.summaryErrors[conversationId] {
    Text("Error: \(error)")
}

// Global states
if aiService.searchLoadingState {
    ProgressView()
}

if let error = aiService.searchError {
    Text("Error: \(error)")
}
```

**After:**
```swift
// Per-conversation states (cleaner API)
if aiCoordinator.summaryService.state.isLoading(conversationId) {
    ProgressView()
}

if let error = aiCoordinator.summaryService.state.error(for: conversationId) {
    Text("Error: \(error)")
}

// Global states (same pattern)
if aiCoordinator.searchService.isLoading {
    ProgressView()
}

if let error = aiCoordinator.searchService.errorMessage {
    Text("Error: \(error)")
}
```

### Step 5: Update Lifecycle Hooks

**Before:**
```swift
aiService.onSignIn()
aiService.onSignOut()
aiService.onMessageMutation(conversationId: id, messageId: msgId)
```

**After:**
```swift
aiCoordinator.onSignIn()
aiCoordinator.onSignOut()
aiCoordinator.onMessageMutation(conversationId: id, messageId: msgId)
```

### Step 6: Update Cache Management

**Before:**
```swift
aiService.clearCaches()
aiService.clearExpiredCachedData()
aiService.reset()
```

**After:**
```swift
aiCoordinator.clearCaches()
aiCoordinator.clearExpiredCachedData()
aiCoordinator.reset()
```

## Benefits of the Refactoring

### 1. Single Responsibility Principle
Each service now has a clear, focused purpose:
- `SummaryService`: Thread summarization only
- `ActionItemsService`: Action item extraction only
- `SearchService`: Semantic search only
- etc.

### 2. Reduced Complexity
- **Before**: 2368-line monolithic file
- **After**: Multiple focused files (100-400 lines each)

### 3. Reusable Infrastructure
Shared components eliminate code duplication:
- `CacheManager<T>`: Generic caching for any `Cacheable` type
- `FeatureState<T>`: Generic state management
- `FirebaseFunctionClient`: Single retry/telemetry implementation
- `TelemetryLogger`: Centralized logging

### 4. Improved Testability
- Services can be tested in isolation
- Shared infrastructure can be mocked
- Easier to write focused unit tests

### 5. Better Type Safety
```swift
// Before: String-keyed dictionaries
var summaryLoadingStates: [String: Bool] = [:]
var summaryErrors: [String: String] = [:]

// After: Strongly-typed state container
let state = FeatureState<ThreadSummaryResponse>()
state.isLoading(conversationId)
state.error(for: conversationId)
state.get(conversationId)
```

### 6. Easier Maintenance
- Changes to one feature don't affect others
- New features can be added as new services
- Infrastructure improvements benefit all services

### 7. Better Encapsulation
- Services manage their own state
- Private implementation details are truly private
- Clear public API boundaries

## Performance Considerations

### No Performance Degradation
- Same underlying Firebase Functions calls
- Same retry logic and telemetry
- Same caching strategies
- Services share infrastructure (no duplication)

### Memory Usage
- Slightly lower: Generic caches replace duplicated cache dictionaries
- Services can be deallocated independently if needed

## Testing Impact

### Unit Testing
**Before:** Hard to test due to tight coupling
```swift
// Had to mock everything just to test one feature
```

**After:** Easy to test in isolation
```swift
// Test summary service independently
let telemetry = TelemetryLogger()
let client = FirebaseFunctionClient(telemetryLogger: telemetry)
let summaryService = SummaryService(functionClient: client, telemetryLogger: telemetry)
// Test...
```

### Integration Testing
Coordinator makes it easy to test feature interactions:
```swift
let coordinator = AIFeaturesCoordinator()
coordinator.configure(...)
// Test coordinated behavior
```

## Common Patterns

### Accessing Services
```swift
// Always go through the coordinator
aiCoordinator.summaryService.summarizeThread(...)
aiCoordinator.actionItemsService.extractActionItems(...)
aiCoordinator.searchService.search(...)
```

### Observing State
```swift
// Per-conversation state
aiCoordinator.summaryService.state.isLoading(conversationId)
aiCoordinator.summaryService.state.error(for: conversationId)
aiCoordinator.summaryService.state.get(conversationId)

// Global state
aiCoordinator.searchService.isLoading
aiCoordinator.searchService.errorMessage
```

### Cache Management
```swift
// Clear specific service cache
aiCoordinator.summaryService.clearCache()
aiCoordinator.summaryService.clearCache(for: conversationId)

// Clear all caches
aiCoordinator.clearCaches()

// Clear expired data
aiCoordinator.clearExpiredCachedData()
```

## Breaking Changes

### Function Name Changes
- `summarizeThreadTask` → `summarizeThread`
- `smartSearch` → `search`

### State Access Changes
- Direct dictionary access → Typed state methods
- `summaryLoadingStates[id]` → `state.isLoading(id)`
- `summaryErrors[id]` → `state.error(for: id)`

## Backward Compatibility

The old `AIFeaturesService.swift` file still exists but should be considered deprecated. It can be safely removed after migration is complete.

## Migration Checklist

- [ ] Replace `AIFeaturesService` with `AIFeaturesCoordinator` in initialization
- [ ] Update all service method calls to go through specific services
- [ ] Update state observations to use new state API
- [ ] Update lifecycle hooks (onSignIn, onSignOut, etc.)
- [ ] Update tests to use new service structure
- [ ] Verify all features still work correctly
- [ ] Remove old `AIFeaturesService.swift` file

## Support

If you encounter issues during migration:
1. Check that all services are properly configured
2. Verify state observations use the new API
3. Ensure service method names are updated (e.g., `summarizeThreadTask` → `summarizeThread`)
4. Check that coordinator methods are used for lifecycle hooks

## Example: Complete Migration

**Before (ChatView.swift):**
```swift
@Environment(\.aiService) private var aiService

// ...

Task {
    do {
        let summary = try await aiService.summarizeThreadTask(
            conversationId: conversation.id
        )
        // Use summary
    } catch {
        print("Error: \(error)")
    }
}

if aiService.summaryLoadingStates[conversation.id] == true {
    ProgressView()
}
```

**After (ChatView.swift):**
```swift
@Environment(\.aiCoordinator) private var aiCoordinator

// ...

Task {
    do {
        let summary = try await aiCoordinator.summaryService.summarizeThread(
            conversationId: conversation.id
        )
        // Use summary
    } catch {
        print("Error: \(error)")
    }
}

if aiCoordinator.summaryService.state.isLoading(conversation.id) {
    ProgressView()
}
```

## Next Steps

1. **Update Environment Key** (if using SwiftUI Environment):
   ```swift
   // Before
   private struct AIServiceKey: EnvironmentKey {
       static let defaultValue: AIFeaturesService? = nil
   }

   // After
   private struct AICoordinatorKey: EnvironmentKey {
       static let defaultValue: AIFeaturesCoordinator? = nil
   }
   ```

2. **Update App Initialization**:
   Replace AIFeaturesService instance with AIFeaturesCoordinator

3. **Migrate Views One by One**:
   Update each view that uses AI features

4. **Run Tests**:
   Verify functionality after each migration step

5. **Clean Up**:
   Remove deprecated code once migration is complete
