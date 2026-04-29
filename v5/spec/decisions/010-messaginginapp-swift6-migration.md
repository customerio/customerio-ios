# ADR 010 — MessagingInApp Swift 6 Concurrency Migration

**Status:** Accepted
**Supersedes:** —
**Superseded by:** —

---

## Context

The `MessagingInApp` module was ported from the original SDK over four phases. The original codebase predated Swift's structured concurrency model and used `Timer`, completion handlers, `@objc` selectors, and `DIGraphShared` for dependency injection. Migrating to Swift 6 with strict concurrency checking required a series of architectural decisions about actor isolation, protocol boundaries, and Sendable conformances.

---

## Decision

### Protocol `Sendable` requirements

All protocols whose conforming types cross actor boundaries must inherit `Sendable` (or `AnyObject, Sendable` for reference-type protocols). Affected protocols:

- `GistDelegate: AnyObject, Sendable` — stored in `Gist` actor; consumed on `@MainActor`
- `SseConnectionManagerProtocol: AnyObject, Sendable` — passed to `CioSseLifecycleManager` actor
- `SseServiceProtocol: AnyObject, Sendable` — passed to `SseConnectionManager` actor
- `SseRetryHelperProtocol: AnyObject, Sendable` — passed to `SseConnectionManager` actor
- `HeartbeatTimerProtocol: AnyObject, Sendable` — passed to `SseConnectionManager` actor
- `SseLifecycleManager: AnyObject, Sendable` — stored in `Gist` actor
- `GistQueueNetwork: Sendable` — passed to `QueueManager` actor
- `Sleeper: Sendable` — captured in Task closures inside `SseRetryHelper` actor
- `ApplicationStateProvider: Sendable` — crossed into `MainActor.run` inside `CioSseLifecycleManager`
- `InAppMessageManager: AnyObject, Sendable` — shared across multiple actors

### `@MainActor` on UI-layer protocols

Delegate protocols for UIKit-backed components are marked `@MainActor` to allow conforming classes to be `@MainActor` without triggering "conformance crosses into main actor-isolated code" errors:

- `GistDelegate`, `GistViewDelegate`, `GistViewLifecycleDelegate` — all `@MainActor`
- `EngineWebDelegate` — `@MainActor`
- `InlineMessageManagerDelegate` — `@MainActor`
- `GistInlineMessageUIViewDelegate` — `@MainActor`

### `InAppMessageManager.subscribe` — keyPath parameter removed

The original protocol declared:
```swift
func subscribe(keyPath: KeyPath<InAppMessageState, some Equatable & Sendable>, subscriber: ...)
```

Generic protocol methods with opaque type parameters cannot be dispatched through `any InAppMessageManager` existentials in Swift 6 without the `KeyPath` being provably `Sendable`. Since `DefaultInAppMessageManager.subscribe` never used the `keyPath` for filtering (it notified on all state changes), the parameter was removed:

```swift
func subscribe(subscriber: InAppMessageStoreSubscriber) async
```

Filtering by key path is a future enhancement, not a current requirement.

### `DefaultNotificationInbox` — per-property `@MainActor`, not class-level

Making the entire `DefaultNotificationInbox` class `@MainActor` caused conformance conflicts because `NotificationInbox: Sendable` requires methods to be callable from non-main-actor contexts. The resolution: remove class-level `@MainActor`, annotate only the mutable properties (`listeners`, `storeSubscriber`) and the methods that access them (`addChangeListener`, `notifyAllListeners`, `subscribeToInboxMessages`, `init`) as `@MainActor`. Methods that only dispatch into Tasks (`markMessageOpened`, `markMessageDeleted`, etc.) remain nonisolated. `filterByTopic` is `nonisolated` because it operates only on value-type arguments.

### `SseConnectionManager` — removed task self-reference capture

The original code created `Task`s with a circular reference:
```swift
var newTask: Task<Void, Never>?
newTask = Task { [weak self, generation] in
    guard let task = newTask else { return }
    await self.executeConnectionAttempt(task: task, generation: generation)
}
```

Capturing a mutable `var` in a `@Sendable` closure is disallowed in Swift 6. The `task` parameter in `executeConnectionAttempt`/`handleStreamEnded` was used only for `streamTask == task` identity checking, which is redundant because `generation` (a monotonically increasing `UInt64`) already uniquely identifies each connection attempt. The `task` parameter was removed and the guard simplified to `generation == activeConnectionGeneration`.

### `EngineWebConfiguration` — `@unchecked Sendable`

`EngineWebConfiguration` stores `[String: AnyEncodable?]?` where `AnyEncodable` wraps `Any`. `Any` is not `Sendable`, making the struct non-conformant. Since `EngineWebConfiguration` is only created and consumed on `@MainActor` (as part of the EngineWeb setup), `@unchecked Sendable` is safe and avoids modifying the third-party `AnyEncodable` implementation.

### `SseLifecycleManager.deinit` — `nonisolated(unsafe)` for observer array

An actor's `deinit` is nonisolated in Swift 6. Accessing actor-isolated mutable state from `deinit` requires `nonisolated(unsafe)`. The `notificationObservers: [NSObjectProtocol]` array is accessed only in `deinit` (to remove observers) and in `setupNotificationObservers` (actor-isolated). Since both paths are sequential by construction (setup happens before teardown), `nonisolated(unsafe)` is safe here.

### `InAppEventListener` — `ListenerBox` wrapper

`InAppEventListener: AnyObject` is a public protocol whose conforming types are not required to be `Sendable`. Crossing a `Task` boundary with `any InAppEventListener` triggers a "data race" diagnostic. Rather than constraining the public protocol with `Sendable` (a breaking change for external adopters), a file-private `ListenerBox: @unchecked Sendable` wrapper is used at the call sites in `Gist` and `MessagingInAppModule`. Callers are responsible for thread-safe access to their listener implementations.

### `trackMetric` closure injection

Analytics metric tracking is decoupled from `GistDelegateImpl` and `DefaultNotificationInbox` via an injected `trackMetric: @Sendable (String, String, [String: String]) async -> Void` closure. This closure captures `[weak root]` where `root` is the `CustomerIO` actor, preventing a retain cycle and allowing the inbox layer to fire `"Report Delivery Event"` tracks without a direct dependency on the root SDK. The `MessagingInAppModule` registers a side effect on `DefaultInAppMessageManager` to forward `.inboxAction(.trackClicked)` through this closure.

### Observer token retention

`CommonEventBus.registerObserver` returns a `RegistrationToken` whose `deinit` immediately deregisters the observer. `MessagingInAppModule` retains all returned tokens in `private var observerTokens: [AnyObject] = []`. Dropping a token — e.g., by ignoring the return value with `_ =` — would silently deregister the observer. This matches the same pattern used in `MessagingPushModule`.

---

## Consequences

**Enables:**
- The `MessagingInApp` module compiles cleanly under Swift 6 strict concurrency.
- Cross-platform build (iOS + macOS) is supported via `#if canImport(UIKit)` guards; `NoOpGistDelegate`, `NoOpSseLifecycleManager`, and `NoOpNotificationInbox` provide safe fallbacks.
- All protocol boundaries are explicit about Sendable requirements, making future test mock injection straightforward.

**Constrains:**
- `InAppMessageManager.subscribe` no longer filters by key path. All subscribers receive callbacks on every state change; per-subscriber filtering must be added if performance demands it.
- `InAppEventListener` adopters are not required to be `Sendable`. If a future Swift version tightens `@unchecked Sendable` boxing semantics, this workaround may need revisiting.
- `EngineWebConfiguration` uses `@unchecked Sendable`; any future change that passes it across thread boundaries must be reviewed for safety.
