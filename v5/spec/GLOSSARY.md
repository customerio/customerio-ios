# CustomerIO iOS SDK — Glossary

Canonical terminology for this project. All code, comments, and documentation
must use these terms exactly. If a term appears in code that is not listed here,
add it before the PR merges.

---

## Core Types

**`Variant`**
The typed discriminated-union value type used for all event properties, traits,
and attributes. Replaces `[String: Any]` across the entire SDK. `Codable`,
`Sendable`, and `Equatable`. Cases: `.string`, `.int`, `.float`, `.bool`,
`.date`, `.data`, `.array`, `.object`, `.null`. Renamed from `Commuted` —
`Variant` is the standard PL-theory term (see `std::variant`, Rust enum
variants). Lives in `Sources/CustomerIO/Variant/`.

**`VariantConvertible`**
Protocol for types that can convert themselves to `Variant` via `asVariant()`.
All standard Swift types (`String`, `Int`, `Double`, `Bool`, `Date`, `Data`,
`Array`, `Dictionary`, `Optional`) conform. Lives in `Sources/CustomerIO/Variant/`.

**`PendingEvent`**
An enum representing an event that has been accepted by the public API but not
yet enriched or queued. Cases: `.track`, `.trackSynthesized`, `.identify`,
`.screen`, `.clearIdentify`, `.setProfileAttributes`, `.setDeviceAttributes`.
`trackSynthesized` bypasses the aggregation stage; all others pass through it.

**`EnrichedEvent`**
An event that has passed through the enrichment stage: timestamp, anonymousId,
and profile context have been resolved. Carries `type`, `name`, `category`,
`properties`, `timestamp`, and `anonymousId`.

**`PersistedEvent`**
An `EnrichedEvent` that has been written to the `event_queue` SQLite table.
Carries a `storageId: Int64` primary key in addition to the event data.

**`AggregationResult`**
The outcome of evaluating an `EnrichedEvent` against the active ruleset.
Cases: `.passThrough` (event proceeds to the queue), `.aggregated` (event
absorbed into an accumulator), `.discarded` (event silently dropped).

**`AggregationRule`**
A server-configured rule that intercepts events by name and applies one or more
`AggregateOperation` values. Carries `id`, `eventRules`, `uploadInterval`,
and `scope` (`.device` or `.profile`).

**`AccumulatorValue`**
A typed slot in an accumulator's state dictionary. Cases: `.int`, `.double`,
`.string`, `.variant`, `.stringSet`, `.histogram`, `.never`. `Codable` for
encrypted persistence across app restarts.

**`Synchronized<T>`**
A thread-safe wrapper for non-`Sendable` values. `@unchecked Sendable`. Provides
`.using { }` for read-only access and `.mutating { }` for mutation. Used wherever
actor-isolated state must be read from `nonisolated` contexts (e.g. `_log`,
`_currentToken` on `MessagingPushModule`).

---

## Protocols

**`CIOModule`**
The protocol all feature modules conform to. Two startup phases:
- Phase 1 (`preActivate`) — synchronous, before the first run-loop cycle
- Phase 2 (`configure`) — async, after the database and pipeline are ready

**`CIOTrackingClient`**
A narrow public protocol abstracting the CustomerIO tracking surface.
`CustomerIO` conforms via an empty extension. Used by sub-modules (e.g.
`MessagingPushModule`) so they can emit metric events without holding a direct
`CustomerIO` reference, enabling mock injection in tests.

**`ProfileEnhancing`**
Optional `CIOModule` protocol. The root calls conforming modules during every
`identify()` to collect additional profile attributes to merge into the payload.

**`PushTokenProvider`**
Protocol abstracting push token delivery. `APNPushProvider` is the
SDK-supplied implementation for APNs. Apps using Firebase implement their own
conformance wrapping `Firebase.Messaging`. The SDK never imports Firebase.

**`FirebaseService`**
Protocol boundary between the FCM push module and Firebase. The app provides
a conforming wrapper. Keeps `MessagingPushFCM` free of any Firebase dependency.

**`DatabaseKeyProvider`**
Protocol for supplying the SqlCipher encryption passphrase. Two implementations:
`ApiKeyDatabaseKeyProvider` (default; uses the CDP API key verbatim) and
`KeychainDatabaseKeyProvider` (generates a per-install 256-bit random key
stored in the platform Keychain).

**`EventBus`**
Protocol for the type-keyed pub/sub bus. Implemented by `CommonEventBus`.
Used for cross-module SDK-internal communication only. App code never
interacts with it directly.

---

## Key Components

**`StorageManager`**
A `struct` (stateless gateway) in `CustomerIO_Utilities`. All data is written
to an encrypted SqlCipher database. Module-specific query methods live in
`extension StorageManager` files inside their owning module — not in the core
struct. Its `db: Database` property is `package` access.

**`AggregationEngine`**
An `actor` that holds the active ruleset and all in-progress accumulators.
Evaluates events, updates accumulator state, and emits synthesised flush events
via an injected `@Sendable (PendingEvent) -> Void` closure.

**`EventProcessor`**
A stateless `struct` whose collaborators are injected as closures. Isolates
the per-event dispatch logic (five branches) from the `AsyncStream`-driving
loop in `CustomerIO`. Fully testable with lambda mocks.

**`PushClickHandler`**
Handles metric tracking when a CIO push notification is clicked or displayed.
Depends on `CIOTrackingClient` (not `CustomerIO` directly) for testability.

**`CommonEventBus`**
The SDK-internal typed pub/sub bus. No logging. Observer handlers run
off-actor. Used by modules to react to SDK lifecycle events (e.g. `ResetEvent`,
`ProfileIdentifiedEvent`).

**`ModuleRegistry`**
An `actor` that stores `[ObjectIdentifier: any CIOModule]`. Modules are
registered during `configure(_:)` and retrieved via `module(ofType:)`.

---

## Events (CIOEvent namespace)

**`CIOEvent.ProfileIdentifiedEvent`** — Posted by `CustomerIO` when `identify()` is called.
**`CIOEvent.AnonymousProfileIdentifiedEvent`** — Posted when anonymous identification occurs.
**`CIOEvent.ScreenViewedEvent`** — Posted by `CustomerIO` when `screen()` is called.
**`CIOEvent.ResetEvent`** — Posted by `CustomerIO` when `clearIdentify()` is called.

---

## Architecture Terms

**`CIOKeys`**
The namespace for all repeated string literals (event names, storage keys, table
names, payload headers). Root enum in `CustomerIO_Utilities`; extended per-module.

**`preActivate`**
Phase 1 of module startup. Runs synchronously before
`application(_:didFinishLaunchingWithOptions:)` returns. Only modules that must
register OS-level delegates (currently `MessagingPushModule`) override the
default no-op.

**`startConfigure`**
The preferred entry point for SDK initialization. Calls `activateModulesForLaunch`
synchronously, then kicks off `configure(_:)` in a `Task`. Calls `onCompletion`
when done (`nil` = success). Satisfies Apple's requirement that
`UNUserNotificationCenter.delegate` be set before the app finishes launching.

**`trackSynthesized`**
A `PendingEvent` case for events emitted internally by the SDK (e.g. flush events
from `AggregationEngine`, `"Device Deleted"` from `unregisterDevice()`). These
bypass the aggregation evaluation stage and go directly to enrichment and the queue.

**`unregisterDevice`**
Public method on `MessagingPushModule`. Emits `"Device Deleted"` to the backend
to disassociate this device from the current user's profile, without affecting
local identity, the system push permission, or the stored token. The token is
retained for automatic re-registration on the next `identify()` profile change.
