# AI Features Service Architecture

## Overview

This directory contains the refactored AI features architecture, which replaces the monolithic `AIFeaturesService` with a modular, composition-based design.

## Directory Structure

```
AI/
├── README.md                           # This file
├── MIGRATION_GUIDE.md                  # Detailed migration instructions
├── AIFeaturesCoordinator.swift         # Main coordinator (entry point)
│
├── Shared/                             # Reusable infrastructure
│   ├── CacheManager.swift              # Generic cache with expiration
│   ├── FeatureState.swift              # Generic state management
│   ├── TelemetryLogger.swift           # Telemetry logging
│   └── FirebaseFunctionClient.swift   # Firebase calls with retry logic
│
└── Features/                           # Individual feature services
    ├── SummaryService.swift            # Thread summarization
    ├── ActionItemsService.swift        # Action item extraction
    ├── SearchService.swift             # Semantic search
    ├── MeetingSuggestionsService.swift # Meeting time suggestions
    ├── SchedulingService.swift         # Scheduling intent detection
    ├── DecisionTrackingService.swift  # Decision tracking
    └── CoordinationInsightsService.swift # Coordination insights & alerts
```

## Quick Start

### 1. Initialize the Coordinator

```swift
let aiCoordinator = AIFeaturesCoordinator()
```

### 2. Configure with Dependencies

```swift
aiCoordinator.configure(
    modelContext: modelContext,
    authService: authService,
    messagingService: messagingService,
    firestoreService: firestoreService,
    networkMonitor: networkMonitor
)
```

### 3. Use Feature Services

```swift
// Summarize a conversation
let summary = try await aiCoordinator.summaryService.summarizeThread(
    conversationId: conversationId
)

// Search messages
let results = try await aiCoordinator.searchService.search(
    query: "project deadline"
)

// Get meeting suggestions
let suggestions = try await aiCoordinator.meetingSuggestionsService.suggestMeetingTimes(
    conversationId: conversationId,
    participantIds: participantIds,
    durationMinutes: 60
)
```

## Architecture Principles

### 1. **Single Responsibility**
Each service handles one specific AI feature:
- `SummaryService`: Thread summarization only
- `ActionItemsService`: Action item extraction only
- `SearchService`: Semantic search only
- etc.

### 2. **Composition Over Inheritance**
Services are composed together in the coordinator rather than inheriting from a common base class.

### 3. **Dependency Injection**
Services receive their dependencies through constructor injection:
```swift
SummaryService(
    functionClient: functionClient,
    telemetryLogger: telemetryLogger
)
```

### 4. **Shared Infrastructure**
Common functionality is extracted into reusable components:
- `CacheManager<T>`: Generic caching
- `FeatureState<T>`: Generic state management
- `FirebaseFunctionClient`: Retry logic & error handling
- `TelemetryLogger`: Analytics logging

## Key Components

### AIFeaturesCoordinator
The main entry point that:
- Owns all feature services
- Manages shared infrastructure
- Coordinates lifecycle hooks
- Handles message observer hooks
- Provides unified cache management

### Shared Infrastructure

#### CacheManager<T>
Generic cache manager for any `Cacheable` type:
```swift
protocol Cacheable {
    var cachedAt: Date { get }
    var isExpired: Bool { get }
}

let cache = CacheManager<CachedSummary>()
cache.set("key", value: cachedSummary)
let cached = cache.get("key")
```

#### FeatureState<T>
Type-safe state container for per-conversation state:
```swift
let state = FeatureState<ThreadSummaryResponse>()
state.setLoading("conversationId", true)
state.isLoading("conversationId") // true
state.setError("conversationId", "Error message")
state.set("conversationId", response)
```

#### FirebaseFunctionClient
Handles all Firebase Cloud Function calls with:
- Exponential backoff retry (max 3 attempts)
- Automatic token refresh
- Telemetry logging
- Error handling

#### TelemetryLogger
Centralized telemetry logging for:
- Success metrics (duration, attempts, cache hits)
- Failure metrics (error types, error messages)
- Analytics to Firestore

### Feature Services

Each feature service follows the same pattern:
1. **State Management**: Observable state via `@Observable` and `FeatureState<T>`
2. **Caching**: In-memory and SwiftData persistence
3. **Error Handling**: Per-conversation error tracking
4. **Dependencies**: Injected through constructor
5. **Public API**: Clean, focused interface

## Usage Examples

### Thread Summarization

```swift
// Get summary with caching
let summary = try await aiCoordinator.summaryService.summarizeThread(
    conversationId: conversationId,
    messageLimit: 50,
    saveLocally: true,
    forceRefresh: false
)

// Check loading state
if aiCoordinator.summaryService.state.isLoading(conversationId) {
    ProgressView()
}

// Handle errors
if let error = aiCoordinator.summaryService.state.error(for: conversationId) {
    Text("Error: \(error)")
}

// Clear cache
aiCoordinator.summaryService.clearCache(for: conversationId)
```

### Semantic Search

```swift
// Perform search
let results = try await aiCoordinator.searchService.search(
    query: "project deadline",
    maxResults: 20,
    forceRefresh: false
)

// Check loading state
if aiCoordinator.searchService.isLoading {
    ProgressView()
}

// Handle errors
if let error = aiCoordinator.searchService.errorMessage {
    Text("Error: \(error)")
}
```

### Meeting Suggestions

```swift
// Get suggestions
let suggestions = try await aiCoordinator.meetingSuggestionsService.suggestMeetingTimes(
    conversationId: conversationId,
    participantIds: ["user1", "user2"],
    durationMinutes: 60,
    preferredDays: 14,
    forceRefresh: false
)

// Track user interaction
await aiCoordinator.meetingSuggestionsService.trackInteraction(
    conversationId: conversationId,
    action: "accept",
    suggestionIndex: 0,
    suggestionScore: suggestions.suggestions[0].score
)

// Check state
if aiCoordinator.meetingSuggestionsService.state.isLoading(conversationId) {
    ProgressView()
}
```

### Scheduling Intent Detection

```swift
// Automatically triggered by message mutations
aiCoordinator.onMessageMutation(
    conversationId: conversationId,
    messageId: messageId
)

// Check if intent was detected
if aiCoordinator.schedulingService.intentDetected[conversationId] == true {
    // Show scheduling suggestions UI
}

// Get confidence score
if let confidence = aiCoordinator.schedulingService.intentConfidence[conversationId] {
    print("Scheduling intent confidence: \(confidence)")
}

// Snooze suggestions
try aiCoordinator.schedulingService.snoozeSuggestions(
    for: conversationId,
    duration: 3600 // 1 hour
)
```

### Coordination Insights

```swift
// Refresh insights (e.g., on app foreground)
await aiCoordinator.refreshCoordinationInsights(forceAnalysis: false)

// Fetch insights for a conversation
if let insight = aiCoordinator.coordinationInsightsService.fetchInsights(
    for: conversationId
) {
    // Display action items, deadlines, blockers, etc.
    for actionItem in insight.actionItems {
        print(actionItem.description)
    }
}

// Fetch all active insights
let allInsights = aiCoordinator.coordinationInsightsService.fetchAllInsights()

// Fetch proactive alerts
let alerts = aiCoordinator.coordinationInsightsService.fetchAlerts(
    for: conversationId
)

// Mark alert as read
try aiCoordinator.coordinationInsightsService.markAlertAsRead(alertId)
```

## Lifecycle Management

### Sign In
```swift
aiCoordinator.onSignIn()
// Automatically refreshes coordination insights
```

### Sign Out
```swift
aiCoordinator.onSignOut()
// Clears all caches and resets services
```

### Message Updates
```swift
aiCoordinator.onMessageMutation(
    conversationId: conversationId,
    messageId: messageId
)
// Triggers scheduling intent detection
```

### Network Reconnection
```swift
await aiCoordinator.processPendingSchedulingSuggestions()
// Processes queued requests when network returns
```

## Cache Management

### Clear All Caches
```swift
aiCoordinator.clearCaches()
```

### Clear Expired Data
```swift
aiCoordinator.clearExpiredCachedData()
// Removes expired summaries, search results, suggestions, etc.
```

### Per-Service Cache Control
```swift
aiCoordinator.summaryService.clearCache()
aiCoordinator.searchService.clearCache()
aiCoordinator.meetingSuggestionsService.clearCache()
```

## Error Handling

All services follow consistent error handling:

```swift
do {
    let summary = try await aiCoordinator.summaryService.summarizeThread(
        conversationId: conversationId
    )
    // Success
} catch AIFeaturesError.unauthorized {
    // User not authenticated
} catch AIFeaturesError.notConfigured {
    // Service not configured
} catch AIFeaturesError.invalidResponse {
    // Invalid response from backend
} catch {
    // Other errors
}
```

## Performance

### Caching Strategy
1. **In-Memory Cache**: Fast access for recent requests
2. **SwiftData Cache**: Persistent storage for offline access
3. **Expiration**: Automatic cleanup of stale data

### Network Optimization
- Exponential backoff retry (3 attempts max)
- Offline queue for scheduling suggestions
- Debouncing for repeated requests
- Cache-first with configurable force-refresh

### Telemetry
All AI calls are logged with:
- Function name
- Duration (ms)
- Success/failure
- Attempt count
- Cache hit/miss
- Error details (if failed)

## Testing

### Unit Tests
Each service can be tested independently:
```swift
func testSummaryService() {
    let telemetry = TelemetryLogger()
    let client = FirebaseFunctionClient(telemetryLogger: telemetry)
    let service = SummaryService(
        functionClient: client,
        telemetryLogger: telemetry
    )

    // Test service behavior
}
```

### Integration Tests
Test coordinated behavior:
```swift
func testCoordinator() {
    let coordinator = AIFeaturesCoordinator()
    coordinator.configure(...)

    // Test feature interactions
}
```

## Migration

See [MIGRATION_GUIDE.md](./MIGRATION_GUIDE.md) for detailed migration instructions from the old `AIFeaturesService`.

## Benefits

1. **Maintainability**: Focused services are easier to understand and modify
2. **Testability**: Services can be tested in isolation
3. **Reusability**: Shared infrastructure reduces code duplication
4. **Type Safety**: Generic state management improves compile-time safety
5. **Scalability**: New features can be added as new services
6. **Performance**: Same caching/retry logic, no degradation
7. **Encapsulation**: Private implementation details stay private

## Contributing

When adding new AI features:

1. Create a new service in `Features/`
2. Use shared infrastructure (`CacheManager`, `FeatureState`, etc.)
3. Follow the pattern established by `SummaryService`
4. Add the service to `AIFeaturesCoordinator`
5. Update this README and migration guide
6. Add unit tests

## License

Same as parent project.
