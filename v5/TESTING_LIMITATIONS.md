# Testing Limitations

This document records components that cannot be covered by unit tests in their
current form, together with the specific blocker and (where applicable) the
abstraction that would unlock testing.

---

## Hard blockers — system framework coupling

These require framework types that have no public initialiser and cannot be
constructed outside of a running app process.

| Component | File | Blocker |
|---|---|---|
| `IOSPushEventListener.handleResponse` / `handleWillPresent` | `Sources/MessagingPush/Push/IOSPushEventListener.swift` | Requires `UNNotificationResponse` and `UNNotification`, which are concrete system types with no public initialiser. Neither can be constructed in a unit-test target. |
| `DeepLinkUtil.open(_:)` | `Sources/MessagingPush/Push/DeepLinkUtil.swift` | Calls `UIApplication.shared.open(...)`. `UIApplication` is unavailable in test targets and cannot be constructed. |
| `PushNotificationCenterRegistrar` | `Sources/MessagingPush/Push/PushNotificationCenterRegistrar.swift` | Wraps `UNUserNotificationCenter.current()`, which requires a running app process to return a usable instance. |
| `AutoTrackingSwizzle` | `Sources/CustomerIO/ScreenTracking/AutoTrackingSwizzle.swift` | Method swizzling is a global, irreversible mutation of the Objective-C runtime. Side effects are process-wide and cannot be isolated between tests. |
| `CoreLocationProvider` | `Sources/Location/CoreLocationProvider.swift` | `CLLocationManager` requires device authorisation and cannot simulate location events in a unit-test host. |
| `LocationCoordinator` | `Sources/Location/LocationCoordinator.swift` | Depends on `CoreLocationProvider`; inherits the same `CLLocationManager` constraint. |
| `GeofenceCoordinator` | `Sources/Geofencing/GeofenceCoordinator.swift` | Drives `CLLocationManager` region monitoring; same constraint as above. |

---

## System daemon / network dependency

| Component | File | Blocker |
|---|---|---|
| `MessagingPushModule.applyToken` / `didFailToRegisterForRemoteNotifications` | `Sources/MessagingPush/MessagingPushModule.swift` | APNs token delivery is driven by the system; `configure` must have run against real module infrastructure first. |
| `AggregationEngine.refreshConfigIfNeeded` | `Sources/CustomerIO/Aggregation/AggregationEngine.swift` | Makes a live HTTP request to fetch ruleset JSON. Requires a network stub (see §Unlockable below). |
| `GeofenceSyncClient` | `Sources/Geofencing/GeofenceSyncClient.swift` | Network-dependent fetch/parse of geofence data. Same unblocking path as `AggregationEngine` above. |
| `GeofenceLoader` | `Sources/Geofencing/GeofenceLoader.swift` | Loads from a live endpoint via `GeofenceSyncClient`. |

---

## Log output — no interception point

| Component | File | Blocker |
|---|---|---|
| `CIOLogger` output assertions | `Sources/CustomerIO/Logging/CIOLogger.swift` | `os_log` does not expose an in-process interception API. Asserting that a specific message was emitted at a given level would require OS-level log streaming (not feasible in XCTest) or replacing `OSLog` with a testable protocol. |

---

## Resource bundle — unavailable in test targets

| Component | File | Blocker |
|---|---|---|
| `AggregationEngine.loadCachedRuleset` (bundle path) | `Sources/CustomerIO/Aggregation/AggregationEngine.swift` | Reads `Bundle.module` for a bundled default ruleset. `Bundle.module` is not available in test targets unless the target declares a `.process("Resources")` source in `Package.swift`. |

---

## Unlockable with modest abstraction

These are currently untested but do not require system framework instances.
A thin protocol or stub is all that is needed.

| Component | What to abstract | Benefit |
|---|---|---|
| `AggregationEngine.evaluate` / `flushIfDue` / `handleReset` | Already uses closure injection for `enqueueEvent`; the actor itself can be constructed with an in-memory `StorageManager`. Closure captures make all observable state inspectable. | Full coverage of aggregation logic without network. |
| `AggregationEngine.refreshConfigIfNeeded` | Introduce a `RulesetClient` protocol over `HttpClient`; inject a `MockRulesetClient` returning canned JSON. `HttpClient` as a protocol already exists. | Network-independent ruleset fetch tests. |
| `GeofenceSyncClient` / `GeofenceLoader` | Same `HttpClient` protocol; inject a mock. | Geofence parse and sync tests. |
| `EventQueue` | Construct with an in-memory `Database`. No additional protocol needed. | Enqueue, dequeue, and ordering tests against real SQLite in memory. |
| `IdentityStore` (direct tests) | None required — `IdentityStore` already takes a `StorageManager`. Currently covered only indirectly via `EventEnricher`. | Explicit persistence tests for `setProfileId`, `clearProfileId`, and anonymousId stability across instances. |
| `CIOLogger` (squelch behaviour) | Replace `OSLog` with a `LogSink` protocol; inject a recording sink in tests. | Verify that messages below the configured level are not emitted and that `%{public}@` formatting is applied correctly. |
