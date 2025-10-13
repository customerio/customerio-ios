# Swift Concurrency Migration Strategy

## Executive Summary

This document outlines the strategy for migrating the Customer.io iOS SDK from pre-Swift 6 concurrency patterns to modern Swift concurrency using actors, async/await, and `@MainActor`. The migration follows an **outside-in approach**, starting with leaf modules and working toward the foundation layer, minimizing risk and validating patterns incrementally.

**Current State:**
- Manual thread safety using `@Atomic`, `Lock`, `Synchronized<T>`
- Callback-based async patterns
- Mixed threading models across modules
- Some actor usage (EventBus, InAppMessageStore)

**Target State:**
- Actor-based isolation for all mutable shared state
- Async/await for asynchronous operations
- `@MainActor` for all UI components
- `Sendable` compliance throughout
- Zero manual locks or `@Atomic` wrappers

**Timeline:** 6 months with 1-2 engineers

---

## Module Architecture Overview

### Dependency Hierarchy

```
                           ┌─────────────────────────────────┐
                           │      Customer App Layer         │
                           └──────────────┬──────────────────┘
                                          │
                     ┌────────────────────┼────────────────────┐
                     │                    │                    │
          ┌──────────▼──────────┐  ┌─────▼─────────┐  ┌──────▼────────┐
          │ MessagingPushAPN    │  │ MessagingInApp│  │ DataPipelines │
          │   (Leaf Module)     │  │ (Leaf Module) │  │ (Leaf Module) │
          └──────────┬──────────┘  └───────┬───────┘  └───────┬───────┘
                     │                     │                    │
          ┌──────────▼──────────┐          │                    │
          │ MessagingPushFCM    │          │                    │
          │   (Leaf Module)     │          │                    │
          └──────────┬──────────┘          │                    │
                     │                     │                    │
                     └──────────┬──────────┴────────────────────┘
                                │
                     ┌──────────▼──────────┐
                     │   MessagingPush     │
                     │  (Middle Module)    │
                     └──────────┬──────────┘
                                │
                     ┌──────────▼──────────┐        ┌──────────────────┐
                     │ CioInternalCommon   │◄───────┤  Migration       │
                     │  (Foundation)       │        └──────────────────┘
                     └─────────────────────┘
```

**Migration Order:** Leaf → Middle → Foundation (Outside-In)

---

## Module Details & Concurrency Issues

### 1. CioInternalCommon (Foundation Module)

**Components:**
- **DI System:** `DIGraphShared`, `DIManager` - Global mutable singleton
- **Storage Layer:** FileStorage, UserDefaults, GlobalDataStore, ProfileStore
- **Event Bus:** Already uses actors ✅
- **Background Queue:** Manual locks, `@Atomic`, file-based persistence
- **Network Layer:** Callback-based async
- **Threading Primitives:** `@Atomic`, `Lock`, `Synchronized<T>`, `ThreadUtil`

**Critical Issues:**
- ❌ DIGraphShared: Global mutable state, no thread safety
- ❌ Storage: Direct UserDefaults access, no actor isolation
- ❌ Queue: Manual locks instead of actor
- ❌ Threading primitives will break in Swift 6
- ✅ EventBus: Already actor-based

**Communication Flow:**
```
Public API → EventBus → Module Subscribers → Background Queue → Network
```

---

### 2. CioDataPipelines (Leaf Module)

**Components:**
- CustomerIO facade (identify, track, screen, device management)
- DataPipelineImplementation (wraps Segment Analytics)
- Plugin architecture (Context, CustomerIODestination, DeviceContextual)
- EventBus integration for cross-module communication

**Critical Issues:**
- ⚠️ No explicit concurrency model (relies on Segment SDK)
- ⚠️ Event handlers run on arbitrary threads
- ⚠️ GlobalDataStore access not isolated
- ⚠️ Device token management has race conditions

**Dependencies:** EventBus (actor), GlobalDataStore

---

### 3. CioMessagingInApp (Leaf Module)

**Components:**
- Gist Provider (singleton) - message fetching and routing
- InAppMessageStore (actor) - Redux-style state management ✅
- QueueManager - network requests for messages
- UI Components: GistView, GistModalViewController, GistInlineMessageUIView
- Message Managers: Modal, Inline, Base
- EngineWeb - WebView wrapper

**Critical Issues:**
- ✅ InAppMessageStore: Already an actor (excellent!)
- ❌ UI Components: Not marked `@MainActor`
- ⚠️ GistDelegate callbacks: Thread safety unclear
- ⚠️ Timer-based polling: Uses `ThreadUtil`
- ❌ Network requests: Callback-based, arbitrary threads

**State Flow:**
```
User Action → dispatch() → Middleware → Reducer → New State
           → Subscribers notified → UI Updates (needs @MainActor)
```

---

### 4. CioMessagingPush (Middle Module)

**Components:**
- MessagingPushImplementation (device token management)
- Push Event Handling: PushEventHandlerProxy, PushClickHandler
- Rich Push: RichPushRequestHandler, RichPushHttpClient, RichPushDeliveryTracker
- PushHistory (singleton) - tracks handled pushes
- EventBus integration

**Critical Issues:**
- ❌ PushEventHandlerProxy: `@Atomic` dictionary + manual Task coordination
- ❌ PushHistory: Lock + `@Atomic` (will break in Swift 6)
- ⚠️ Delegate callbacks: May run on background threads
- ⚠️ Rich Push: Callback-based network, thread unclear

**Communication:**
```
iOS System → UNUserNotificationCenterDelegate → EventBus
          → DataPipelines/Background Queue
```

---

### 5. CioMessagingPushAPN & CioMessagingPushFCM (Leaf Modules)

**Components:**
- Thin wrappers around MessagingPush
- Platform-specific token handling (APN Data vs FCM String)
- Auto-fetch device token integration

**Critical Issues:**
- ✅ Minimal logic, mostly delegates
- ✅ No internal state
- ⚠️ Inherits all parent module issues

---

## Outside-In Migration Strategy

### Why Outside-In?

1. **Low Risk Start:** Leaf modules have fewer dependencies
2. **Pattern Validation:** Test actor approach before foundation work
3. **Incremental Value:** Each phase delivers working improvements
4. **Minimize Cascading Changes:** Foundation changes last prevent rework

---

## Phase 1: Leaf Modules (Months 1-2)

### 1.1 MessagingPushAPN & MessagingPushFCM
**Timeline:** Week 1  
**Priority:** HIGH (Quick Win)  
**Complexity:** LOW

**Changes:**
- Add `@Sendable` to all completion handlers
- Document thread safety guarantees
- Verify no hidden state

**Outcome:** Build confidence, establish patterns, no breaking changes

---

### 1.2 DataPipelines
**Timeline:** Weeks 2-3  
**Priority:** HIGH  
**Complexity:** MEDIUM

**Actor Candidate:**
```
┌────────────────────────────────────────────────┐
│ DataPipelineCoordinator (actor) - NEW         │
│                                                │
│ Responsibilities:                              │
│ • Serialize all identify/track calls           │
│ • Manage device token state                    │
│ • Coordinate with storage layer                │
│                                                │
│ Benefits:                                      │
│ • Single actor for all DataPipeline state      │
│ • No locks needed                              │
│ • Clean async boundaries                       │
└────────────────────────────────────────────────┘
```

**Changes:**
- Create DataPipelineCoordinator actor
- Wrap Segment Analytics access in actor
- Make event handlers `@Sendable`
- Use async alternatives for event subscription
- Remove direct GlobalDataStore access

**Public API:** Remains synchronous via `Task { await coordinator.method() }`

---

### 1.3 MessagingInApp
**Timeline:** Weeks 3-5  
**Priority:** HIGH  
**Complexity:** MEDIUM

**Actor Strategy:**
- ✅ Keep InAppMessageStore as actor (already correct!)
- Mark all UIKit components with `@MainActor`
- Make GistDelegate a `@MainActor` protocol
- Convert Gist provider callbacks to async
- Update QueueManager for async networking

**Changes:**
- `@MainActor` for: GistView, GistModalViewController, GistInlineMessageUIView
- `@MainActor` protocol: GistDelegate
- Remove manual `Task { @MainActor in }` calls
- Async network operations in QueueManager

**Why This Order:**
- Validates actor pattern (InAppMessageStore already works)
- UI components are self-contained
- Minimal impact on other modules

---

## Phase 2: Middle Module (Month 3)

### 2.1 MessagingPush
**Timeline:** Weeks 6-8  
**Priority:** MEDIUM  
**Complexity:** HIGH

**Actor Candidate:**
```
┌────────────────────────────────────────────────┐
│ PushCoordinator (actor) - NEW                 │
│                                                │
│ Responsibilities:                              │
│ • Manage push history                          │
│ • Coordinate event handlers                    │
│ • Serialize push metric tracking               │
│                                                │
│ Replaces:                                      │
│ • PushHistory (Lock + @Atomic)                 │
│ • PushEventHandlerProxy (@Atomic delegates)    │
└────────────────────────────────────────────────┘
```

**Changes:**
- Convert PushHistory to actor methods
- Convert PushEventHandlerProxy to actor
- Update RichPush to async/await
- Make push delegates `@MainActor` where appropriate
- Remove all Lock and `@Atomic` usage

**Benefits:**
- Thread-safe push tracking without locks
- Clean handler coordination
- Proper main thread guarantees for delegates

---

## Phase 3: Foundation Module (Months 4-6)

This is the most critical phase. Foundation changes affect all modules.

### 3.1 Storage Layer
**Timeline:** Weeks 9-11  
**Priority:** CRITICAL  
**Complexity:** VERY HIGH

**Actor Candidate:**
```
┌────────────────────────────────────────────────┐
│ StorageCoordinator (actor) - NEW              │
│                                                │
│ Responsibilities:                              │
│ • All FileStorage operations                   │
│ • All UserDefaults operations                  │
│ • Global data store access                     │
│ • Profile store access                         │
│                                                │
│ Replaces:                                      │
│ • Direct UserDefaults access                   │
│ • FileStorage locks                            │
│ • GlobalDataStore                              │
│ • ProfileStore                                 │
└────────────────────────────────────────────────┘
```

**Changes:**
- Create StorageCoordinator actor
- All storage operations become async
- Update all callers to use `await`
- Remove manual locks from FileStorage
- Serialize all UserDefaults access

**Impact:** High - All modules read/write storage

---

### 3.2 Background Queue System
**Timeline:** Weeks 12-15  
**Priority:** CRITICAL (Most Complex)  
**Complexity:** VERY HIGH

**Actor Candidate:**
```
┌────────────────────────────────────────────────┐
│ QueueCoordinator (actor) - NEW                │
│                                                │
│ Responsibilities:                              │
│ • Queue inventory management                   │
│ • Task scheduling                              │
│ • Queue runner coordination                    │
│ • All storage operations via StorageActor      │
│                                                │
│ Replaces:                                      │
│ • FileManagerQueueStorage (Lock)               │
│ • QueueInventoryMemoryStore (@Atomic)          │
│ • CioQueue                                     │
└────────────────────────────────────────────────┘
```

**Changes:**
- Single actor for entire queue system
- Queue tasks become async functions
- Use `Task.sleep` for retry delays
- Remove all locks and `@Atomic`
- Integrate with StorageCoordinator
- Async network calls for queue tasks

**Why Last:**
- Most complex component
- Everything depends on it
- Requires storage layer to be actor-based first
- Highest risk of breaking changes

**Key Design Decision:** One actor for entire queue (not separate actors for inventory, storage, runner) to avoid actor reentrancy issues.

---

### 3.3 Network Layer
**Timeline:** Weeks 16-17  
**Priority:** MEDIUM  
**Complexity:** LOW

**Changes:**
- Add async alternatives to HttpClient
- Keep callback-based for backward compatibility
- Make all closures `@Sendable`
- Document threading behavior

**Strategy:** Additive changes only, no breaking changes

---

### 3.4 EventBus
**Timeline:** Week 18  
**Priority:** LOW  
**Complexity:** LOW

**Status:** ✅ Already mostly actor-based!

**Changes:**
- Ensure all event types are `Sendable`
- Mark observer closures as `@Sendable`
- Document threading guarantees
- Minor cleanup only

---

### 3.5 DI System
**Timeline:** Weeks 19-20  
**Priority:** MEDIUM  
**Complexity:** MEDIUM

**Strategy:** Make DIGraphShared `Sendable` with lazy actor initialization (not convert to actor)

**Changes:**
- Make DIGraphShared immutable after initialization
- Store actors instead of concrete types
- Use lazy actor initialization
- Remove mutable dictionaries for overrides
- Make override mechanism actor-based

**Rationale:** Converting DI system to actor would force all dependency access to be async, breaking too much code. Instead, make it safely `Sendable`.

---

## Actor Design Patterns

### Pattern 1: Coordinator Actor (Recommended)

**Use For:** Storage, Queue, Push, DataPipeline

**Characteristics:**
- Single actor coordinates all state for a domain
- Public API can remain synchronous
- Internal operations use `await`

**Example Structure:**
```swift
actor DomainCoordinator {
    private var state: DomainState
    
    func performAction() async -> Result {
        // Serialized automatically by actor
    }
}

// Public facade stays synchronous
class PublicAPI {
    private let coordinator: DomainCoordinator
    
    func syncMethod() {
        Task { await coordinator.performAction() }
    }
}
```

---

### Pattern 2: Store Actor

**Use For:** State management (Redux-style)

**Characteristics:**
- Already implemented in InAppMessageStore ✅
- State updates through reducers
- Subscriber pattern for observers

**Example:** InAppMessageStore (keep as-is)

---

### Pattern 3: @MainActor for UI

**Use For:** All UIKit/SwiftUI components

**Characteristics:**
- Guaranteed main thread execution
- No manual thread hopping
- Clear contract for callers

**Apply To:**
- All UIViewController subclasses
- All UIView subclasses
- All UI-facing delegate protocols

---

## Migration Principles

### 1. Outside-In = Least Disruption
- Leaf modules first builds confidence
- Foundation last prevents cascading changes
- Each phase independently valuable

### 2. One Actor Per Domain
- Storage = 1 actor
- Queue = 1 actor
- Push = 1 actor
- DataPipeline = 1 actor
- Don't over-actor (avoid actor reentrancy issues)

### 3. Public APIs Stay Synchronous
- Use `Task { await actor.method() }` internally
- Customers don't need to change code
- Add async alternatives as additions, not replacements

### 4. @MainActor Only for UI
- ViewControllers, Views, UI delegates
- Not business logic
- Not storage or network code

### 5. Validate Each Phase
- Run full test suite after each module
- Monitor performance benchmarks
- Thread Sanitizer in CI
- No regressions before proceeding

### 6. Backward Compatibility
- Deprecate, don't remove
- Provide migration guides
- Support old patterns for 2-3 releases

---

## Risk Mitigation

### Performance Risks
- **Risk:** Actor contention, slower than locks
- **Mitigation:** Profile before/after, optimize hot paths, strategic actor boundaries

### Breaking Change Risks
- **Risk:** Async APIs incompatible with sync contexts
- **Mitigation:** Maintain compatibility layer, additive changes only

### Testing Complexity Risks
- **Risk:** Actors harder to mock
- **Mitigation:** Design protocols carefully, use dependency injection, create test helpers

### Timeline Risks
- **Risk:** Migration takes longer than expected
- **Mitigation:** Phased rollout per module, can ship partial improvements

---

## Success Metrics

### Code Quality
- ✅ Zero `@Atomic` usage
- ✅ Zero `Lock` usage
- ✅ Zero Thread Sanitizer warnings
- ✅ All UI components marked `@MainActor`
- ✅ All shared mutable state actor-isolated

### Performance
- ✅ No regression in queue throughput
- ✅ No regression in API response time
- ✅ No increase in memory usage
- ✅ No increase in battery usage

### Developer Experience
- ✅ Clear actor boundaries documented
- ✅ Async alternatives available
- ✅ Migration guide for customers
- ✅ Thread safety guarantees documented

---

## Timeline Summary

```
Month 1-2: Leaf Modules
├─ Week 1:    MessagingPushAPN/FCM (minimal work)
├─ Week 2-3:  DataPipelines (new actor)
└─ Week 3-5:  MessagingInApp (UI + existing actor)

Month 3: Middle Module
└─ Week 6-8:  MessagingPush (push coordinator actor)

Month 4-6: Foundation
├─ Week 9-11:  Storage Layer (StorageCoordinator actor)
├─ Week 12-15: Background Queue (QueueCoordinator actor) ← CRITICAL
├─ Week 16-17: Network Layer (async APIs)
├─ Week 18:    EventBus (minimal - already actor)
└─ Week 19-20: DI System (Sendable compliance)

Month 6+: Cleanup & Validation
├─ Remove all @Atomic usage
├─ Remove all Lock usage
├─ Remove ThreadUtil where possible
├─ Full integration testing
├─ Performance benchmarking
└─ Documentation updates
```

**Total Duration:** 6 months with 1-2 engineers

---

## Next Steps

1. **Enable Strict Concurrency Warnings** in build settings
2. **Run Thread Sanitizer** to identify current data races
3. **Create Proof of Concept** for one actor pattern
4. **Document Current Threading Assumptions** in each module
5. **Begin Phase 1** with MessagingPushAPN/FCM

---

## References

- [Swift Concurrency Documentation](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [Swift Evolution: Actors](https://github.com/apple/swift-evolution/blob/main/proposals/0306-actors.md)
- [Swift 6 Migration Guide](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/)
- Customer.io Internal: [BACKGROUND-QUEUE.md](./BACKGROUND-QUEUE.md)

---

*This strategy document should be treated as a living document and updated as the migration progresses and new insights are gained.*

