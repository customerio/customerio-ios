# CustomerIO iOS SDK — Reimplementation Architecture

> **DEPRECATED** — This document has been superseded by the `/spec` directory.
> Canonical documentation now lives in:
> - Domain model and module graph: [`/spec/domain/domain-model.md`](/spec/domain/domain-model.md)
> - Feature specs: [`/spec/features/`](/spec/features/)
> - Architecture Decision Records: [`/spec/decisions/`](/spec/decisions/)
> - Public API surface: [`/spec/interfaces/public-api.md`](/spec/interfaces/public-api.md)
> - Glossary: [`/spec/GLOSSARY.md`](/spec/GLOSSARY.md)
>
> This file is retained for historical reference only. Do not update it.
> Last updated: March 18, 2026.

---

## Goals

1. **Restructure modules** so `CustomerIO` is the root and everything else is a peer module underneath it.
2. **Eliminate static globals** — no singleton access patterns inside the SDK itself.
3. **Encrypted storage** — all data written to disk uses SqlCipherKit.
4. **Remove the Analytics (cdp-analytics-swift) dependency** — own the full event pipeline.
5. **Dynamic event aggregation** — server-configured rules intercept events before upload.
6. **Improved testability** — no static state; all dependencies resolved via the container.
7. **Swift 6.2 with actor-based concurrency** — strict concurrency throughout.

---

## Rationale: Removing the Analytics (cdp-analytics-swift) Dependency

The decision to remove `cdp-analytics-swift` and own the full event pipeline is driven by two primary technical requirements, with a third secondary benefit.

### Primary: Encrypted Storage

`cdp-analytics-swift` writes its event queue to a plain SQLite database. Events routinely carry PII — user identifiers, traits, and behavioral data. There is no way to encrypt that storage without forking the library's storage layer. CIO already maintains a fork, so this is technically possible, but every upstream merge would require re-applying changes against the most sensitive part of the library. SqlCipherKit solves the problem cleanly only if the SDK owns the queue entirely.

### Primary: Swift 6.2 Strict Concurrency

`cdp-analytics-swift` was not written with `Sendable` enforcement or actor isolation. Depending on it in a strict-concurrency Swift 6.2 package produces either suppressed warnings hiding real data races, or `@preconcurrency` wrappers that defeat the purpose of the migration. A clean Swift 6.2 codebase is structurally incompatible with this dependency in its current form.

### Secondary: Aggregation Engine Flexibility

The server-driven aggregation model (count accumulation, property stats, discard rules, flush scheduling) does not map cleanly onto the upload-on-drain assumptions built into analytics-swift's scheduler. Owning the pipeline makes the aggregation engine a natural first-class citizen rather than a workaround layered on top of a library designed for different assumptions.

### Risk: Upload/Retry Pipeline Complexity

The area of analytics-swift most worth preserving as reference material — not reinventing — is the **upload/retry/batching pipeline**: exponential backoff with jitter, deduplication across restarts, ordering guarantees, and partial-batch failure handling. These have years of production hardening. The new implementation should treat the analytics-swift source as specification for this layer, not as something to improve upon from scratch.

---

## Module Graph

```
┌──────────────────────────────────────────────────────────┐
│                   CustomerIO_Utilities                    │
│  (internal — never imported directly by app developers)  │
│                                                          │
│  Synchronized · Variant/VariantConvertible · DependencyContainer│
│  Resolver · Autoresolvable · DefaultInitializable        │
│  CommonEventBus · RegistrationToken                      │
│  HttpClient · JsonAdapter · Logger · DateUtil            │
│  SqlCipherKit storage primitives                         │
└─────────────────────────┬────────────────────────────────┘
                          │ (internal dependency)
           ┌──────────────▼──────────────────┐
           │          CustomerIO              │
           │  (root public module)            │
           │                                 │
           │  identify · track · screen       │
           │  Event pipeline                 │
           │  Aggregation engine             │
           │  Upload scheduler               │
           │  SdkConfig / SdkConfigBuilder   │
           │  StorageManager (SqlCipher)     │
           │  Module registry                │
           └──┬──────────┬───────┬───────────┘
              │          │       │
    ┌─────────▼──┐  ┌──────────────┐  ┌▼──────────────────┐  ┌────────────────────┐
    │  Location  │  │MessagingPush │  │   MessagingInApp   │  │  LiveActivities    │  ...
    │  module    │  │(APN or FCM   │  │                    │  │  (iOS 16.1+ only)  │
    └────────────┘  │via provider) │  └────────────────────┘  └────────────────────┘
                    └──────────────┘
```

`CustomerIO_Utilities` is the successor to `CioInternalCommon`. Its products are **not** exposed as a public SPM library under normal circumstances. Sub-modules depend on it internally but app code never imports it directly.

---

## Primitives Incorporated from SwiftPrimitives

The following types are copied (not referenced as a package dependency) from `SwiftPrimitives` into `CustomerIO_Utilities`:

| Type | Purpose |
|------|---------|
| `Synchronized<T>` | Thread-safe wrapper for non-`Sendable` values; replaces `@Atomic`, `Lock`, `LockManager` |
| `Variant` / `VariantConvertible` | Type-safe, `Codable`, `Sendable` discriminated-union value type for event properties; replaces `[String: Any]`. Renamed from `Commuted`/`Commutable` — `Variant` is the standard term for tagged unions in PL theory and has cross-language precedent (`std::variant`, Rust enum variants), while `Commuted` was opaque. The protocol method is `asVariant()` following Swift's `as`-prefixed conversion convention. |
| `DependencyContainer` + `Builder` | Immutable-after-build DI container; replaces `DIGraphShared` |
| `Resolver` | Protocol for resolving dependencies inside factories |
| `Autoresolvable` | Protocol for types that can initialize themselves from a `Resolver` |
| `DefaultInitializable` | Protocol for types with a plain `init()` that the container can auto-create |
| `CommonEventBus` + `RegistrationToken` | Typed, `Sendable` pub/sub bus; replaces `EventBusHandler` |

---

## Configuration & Initialization

### SdkConfigBuilder

Each module extends `SdkConfigBuilder` to add its own configuration surface. App code calls one root builder and gets all options in one place, with nested closure builders for each module:

```swift
import CustomerIO
import CustomerIO_Location
import CustomerIO_MessagingPush

let config = SdkConfigBuilder(cdpApiKey: "…")
    .logLevel(.debug)
    .location {                               // added by Location module
        LocationConfigBuilder(.continuous)    // LocationMode is a required argument
    }
    .geofencing {                             // Added by the Geofence module
        GeofenceConfigBuilder(.automatic)     // GeofenceMode is a required argument
            .syncURL(url)
    }
    .push {                                   // added by Push module
        PushConfigBuilder(provider: APNPushProvider())   // or pass your own PushTokenProvider
            .autoTrackPushEvents(true)
            .appGroupIdentifier("group.io.customer.myapp")
    }
    .build()

let cio = CustomerIO()

// Recommended: fire-and-forget. Calls activateModulesForLaunch synchronously
// before starting the Task, then calls onCompletion when done (nil = success).
cio.startConfigure(config) { error in
    if let error { print("SDK configure failed: \(error)") }
}

// Safe to call from any thread, any isolation domain, before or after configure().
cio.track("app_launched")
```

`startConfigure` is the preferred entry point because it calls
`activateModulesForLaunch(_:)` synchronously — before
`application(_:didFinishLaunchingWithOptions:)` returns — satisfying Apple's
requirement that `UNUserNotificationCenter.delegate` be assigned before the app
finishes launching. If you use the async path instead, you must call
`activateModulesForLaunch` manually before scheduling the configure task:

```swift
// Manual async path (only if you need to await configure):
cio.activateModulesForLaunch(config)   // synchronous — must be here
Task { try await cio.configure(config) }
```

`SdkConfig` is a value type (`struct`) carrying all resolved configuration. Module-specific config is stored as optional sub-structs on `SdkConfig`, keyed by module.

### Module Config Builder Pattern

Module configuration uses **value-type nested-closure builders**. Each module defines its own builder struct and a corresponding `SdkConfigBuilder` extension.

**Extension signature** (defined in the module target):

```swift
// In CustomerIO_Location:
extension SdkConfigBuilder {
    public func location(_ configure: () -> LocationConfigBuilder) -> Self {
        appendingModule { LocationModule(config: configure().build()) }
    }
}
```

The closure returns a `Builder` struct by value — no `@escaping` annotation is needed because the closure is called immediately and never stored.

**Builder struct** (one per module or sub-module config):

```swift
public struct LocationConfigBuilder {
    private var config: LocationConfig

    // LocationMode is required — a zero-arg builder would produce a config
    // indistinguishable from "module not registered", making it semantically
    // meaningless to call `.location { LocationConfigBuilder() }`.
    public init(_ mode: LocationMode) {
        config = LocationConfig(mode: mode)
    }

    public func visitedTilesCap(_ cap: Int) -> Self {
        var copy = self; copy.config.visitedTilesCap = cap; return copy
    }

    public func geofencing(_ configure: () -> GeofenceConfigBuilder) -> Self {
        var copy = self; copy.config.geofenceConfig = configure().build(); return copy
    }

    internal func build() -> LocationConfig { config }
}
```

**Rules for required vs. optional `init` arguments:**

| Scenario | `init` form |
|---|---|
| Zero-arg builder == "module inactive" (e.g. `LocationMode.off` is the off-switch) | Require the primary mode param: `init(_ mode: LocationMode)` |
| Builder always produces a valid default config (e.g. push defaults are well-defined) | No-arg `init()` is fine |

Omitting the `.location { … }` call entirely is the canonical way to not register a module; a builder whose only valid configuration is the default non-op state should not exist as a zero-arg form.

**`build()` is `internal`** — callers never invoke it directly; only the `SdkConfigBuilder` extension does. This enforces that the builder is always consumed through the fluent API.

### Three-Phase Module Startup

All modules conform to a `CIOModule` protocol with three startup phases:

```swift
public protocol CIOModule: Autoresolvable, AnyObject {
    /// Phase 1 (synchronous): register OS-level delegates before the first run-loop cycle.
    nonisolated func preActivate(_ config: SdkConfig)   // default: no-op

    /// Phase 2 (synchronous): pure DI init via Autoresolvable.
    /// `init(resolver:)` is satisfied by Autoresolvable.

    /// Phase 3 (async): receive resolved config, storage, and root reference.
    func configure(_ config: SdkConfig, storage: StorageManager, root: CustomerIO) async throws
}
```

**Phase 1** runs synchronously inside `activateModulesForLaunch(_:)`, which is
called before `application(_:didFinishLaunchingWithOptions:)` returns. Only
modules that need to register OS-level delegates (currently
`MessagingPushModule`, which registers the `UNUserNotificationCenter` delegate)
override `preActivate`. All others inherit the no-op default.

**Phase 2** runs inside `configure(_:)` as each module is instantiated via its
`Autoresolvable` conformance.

**Phase 3** runs inside `configure(_:)` after the database and pipeline are
ready. Each module receives the resolved config, shared storage, and a
back-reference to the root actor. The event bus is not passed as a separate
parameter — modules access it via `root.eventBus`, which is a `nonisolated
package let` readable from any context without `await`.

### Module Accessors via Extensions

When an app imports a module, that module's target extends `CustomerIO` to expose a typed accessor:

```swift
// In CustomerIO_Location:
extension CustomerIO {
    public var location: LocationModule {
        get throws { try modules.require(LocationModule.self) }
    }
}
```

This means `cio.location` compiles only when the Location module is imported and initialized. Accessing a module that was never configured throws a descriptive error rather than returning nil or crashing.

`CustomerIO` owns modules via an internal `ModuleRegistry` — a concurrent-safe actor that holds `[ObjectIdentifier: any CIOModule]`.

---

## Dependency Injection

`DIGraphShared` and all its static patterns are eliminated. The `DependencyContainer` is constructed once during `configure(_:)` and then passed to modules as a `Resolver`. Sub-modules receive the `Resolver` in `init(resolver:)` and pull only what they need. There is no global handle to the container after construction.

### Registration Sources

The container is assembled from three ordered sources during `CustomerIO.configure(_:)`:

1. **Core registrations** — `CustomerIO_Utilities` primitives (`HttpClient`, `StorageManager`, `EventBus`, `Logger`, etc.) registered by the root.
2. **Module registrations** — each module config registered with `SdkConfigBuilder` contributes its own dependencies via `registerDependencies`. The `CIOModuleConfig` protocol requires this method:

```swift
public protocol CIOModuleConfig: Sendable {
    associatedtype Module: CIOModule
    func registerDependencies(into builder: inout DependencyContainer.Builder)
}
```

Each module is responsible for registering its own concrete types and protocol mappings, keeping registration logic colocated with the module rather than centralised in a single generated file.

3. **User overrides** — additional registrations provided through `SdkConfigBuilder.override(as:factory:)`, applied last.

```swift
let config = SdkConfigBuilder(cdpApiKey: "…")
    .override(as: HttpClient.self) { _ in MyCustomHttpClient() }
    .build()
```

### Registration Ordering Guarantee

`DependencyContainer.Builder` is a value type and last-registration-wins per type key. The ordering above is fixed and enforced by `configure(_:)` — user overrides are always applied after all module `registerDependencies` calls, so a module can never clobber a user-supplied override regardless of module registration order.

### Automatic Resolution

Many types require no explicit registration at all:

- Types conforming to `Autoresolvable` are constructed by the container on demand via `init(resolver:)`.
- Types conforming to `DefaultInitializable` are constructed via plain `init()`.

Explicit registrations are only needed for protocol-to-concrete mappings, types requiring `SdkConfig`-derived values, singletons with complex setup, and user overrides. This keeps the total explicit registration surface small and readable without a code generator.

### Testing

In tests, a separate container is built with mock registrations substituted for real ones. No global state needs resetting between tests — each test constructs its own container.

---

## Event Pipeline

The Analytics package is removed entirely. The SDK owns the full pipeline:

```
track(_:properties:) / identify(_:traits:) / screen(_:category:properties:)
        │
        ▼
  [Enrichment Stage]
  • Timestamp, anonymousId, device context
  • IdentifyContextPlugin equivalent (profile attributes)
  • ProfileEnhancing modules called here (see Module Protocols)
        │
        ▼
  [Aggregation Stage]  ◄── server-driven rules (see below)
        │
        ▼
  [Event Queue]  (SqlCipher-backed, encrypted)
        │
        ▼
  [Upload Scheduler]
  • Batch assembler (count- or time-triggered)
  • HTTP upload to CIO API
  • Retry with exponential backoff
  • Delete on acknowledgement
```

All stages are internal. There is no public plugin protocol for customer code to intercept this pipeline.

### Internal Event Bus

`CommonEventBus` is used for **cross-module** communication within the SDK (e.g., Push tells CustomerIO a token was registered; Location tells CustomerIO a geofence was entered). This is distinct from the user-facing event pipeline. App code does not interact with the bus.

---

## Dynamic Event Aggregation

### Overview

When the SDK starts (and periodically thereafter), it fetches an aggregation config from a server-defined endpoint. The config is a JSON document that describes a list of `AggregationRule` objects. Rules are evaluated against every event before it enters the queue.

### Rule Types

```swift
public enum AggregationRule: Codable, Sendable {

    /// Count occurrences of a named event. Upload a summary event on the
    /// defined flush schedule rather than every individual event.
    case count(CountRule)

    /// Collect min/max/sum/count for a numeric property of a named event.
    /// Upload a stats summary on the flush schedule.
    case stats(StatsRule)

    /// Silently discard events matching the filter.
    case discard(DiscardRule)
}
```

Each rule carries:
- `eventName: String` — the event to match (exact or wildcard TBD)
- `flushSchedule: FlushSchedule` — a minimum elapsed duration (e.g. 7 days, 24 hours); treated as "no sooner than"
- Rule-specific fields (property key for stats, output event name for count/stats)

### Aggregator Lifecycle

- Rules are persisted encrypted to SqlCipher after download so they survive restarts.
- An `AggregationEngine` actor holds the active ruleset and all in-progress accumulators.
- Accumulators are also persisted encrypted so partial counts survive app kills.
- On flush, the engine synthesizes a derived event, injects it into the pipeline via a stored `@Sendable (PendingEvent) -> Void` closure, and resets the accumulator.
- Events matching a `discard` rule are dropped at the aggregation stage and never reach the queue.

### Event Processing Loop

The `CustomerIO` actor runs a single `Task` that drains `AsyncStream<PendingEvent>` for the lifetime of the SDK. The per-event dispatch logic is isolated in `EventProcessor` — a stateless `struct` whose collaborators are injected as closures:

```swift
let processor = EventProcessor(
    enrich:         { try await enricher.enrich($0) },
    evaluate:       { try await aggregation.evaluate($0) },
    enqueue:        { try await eventQueue.enqueue($0) },
    uploadIfNeeded: { await scheduler.uploadIfNeeded() }
)
Task {
    for await pending in eventStream {
        await processor.process(pending)
    }
}
```

This separates the stream-driving loop (untestable without a full configure path) from the dispatch logic (fully testable by passing lambda mocks). Tests exercise all five branches — nil enrich, `trackSynthesized` bypass, `.aggregated`, `.discarded`, and `.passThrough` — without constructing a database or scheduler.

### AggregationEngine Back-Reference

`AggregationEngine` needs to inject synthesised flush events back into the pipeline. Rather than holding a back-reference to the `CustomerIO` actor, it stores a single `@Sendable (PendingEvent) -> Void` closure supplied at init time:

```swift
// CustomerIO.configure
let aggregation = AggregationEngine(
    storage: storage,
    httpClient: httpClient,
    sdkConfig: config,
    enqueueEvent: { [weak self] event in self?.enqueueEvent(event) }
)
```

This avoids a retain cycle (the closure captures `CustomerIO` weakly), keeps `AggregationEngine` free of any direct `CustomerIO` type dependency, and makes the engine straightforward to test — a test can pass a simple `{ events.append($0) }` lambda without constructing any SDK infrastructure.

### Flush Scheduling

Flush schedules in rule configs are **minimum durations**, not exact times. The engine only checks for due flushes at **app lifecycle events** (foreground, background, and SDK startup). This avoids background timer overhead and matches the natural checkpoint rhythm of an iOS app. A flush that is overdue by the time the next lifecycle event fires simply runs then.

Flush check points:
- App enters foreground
- App enters background (before the process is suspended)
- `CustomerIO.configure(_:)` completes (catches flushes overdue from the previous session)

### Config Refresh

The aggregation config endpoint is a **static path relative to the region base URL**. The exact path is TBD and should be defined in a single constant so it can be updated without touching call sites. The `CustomerIO` root fetches the config on startup and re-fetches on app foreground, subject to a **minimum refresh interval of 24 hours** — if the last successful fetch was less than 24 hours ago, the cached config is used and no network request is made. The last fetch timestamp is persisted to `sdk_meta` so the rate limit survives app restarts. The `AggregationEngine` can be swapped to a new ruleset atomically without losing in-progress accumulator state. There is no user-configurable refresh interval.

---

## Storage Layer

All data written to disk uses **SqlCipherKit**. `UserDefaults` and flat-file JSON (`EventStorageManager`) are removed.

### Tables

| Table | Contents | Encrypted |
|-------|----------|-----------|
| `identity` | Current profile ID, anonymous ID | Yes |
| `device` | Push token, device attributes | Yes |
| `event_queue` | Pending upload events (`Variant`-serialized) | Yes |
| `aggregation_rules` | Cached server rule config | Yes |
| `aggregation_state` | In-progress accumulator values | Yes |
| `sdk_meta` | Version, install date, migration flags | Yes |
| `live_activity_state` | Active Live Activity tokens and metadata (iOS 16.1+) | Yes |

### StorageManager Extension Pattern

`StorageManager` is a `struct` in `CustomerIO_Utilities`. Its `db: Database` property is `package` access — visible to all targets within the Swift package, but not to external consumers.

Module-specific query methods live in `extension StorageManager` files inside their owning module rather than in the core struct. This keeps `CustomerIO_Utilities` free of schema knowledge that belongs to higher-level modules, and ensures that module-specific methods are only callable when that module's migration has been registered.

| Extension file | Module | Tables used |
|---|---|---|
| `StorageManager+EventQueue.swift` | `CustomerIO` | `event_queue` |
| `StorageManager+Aggregation.swift` | `CustomerIO` | `aggregation_rules`, `aggregation_state` |
| `StorageManager+Geofences.swift` | `CustomerIO_Geofencing` | `geofences`, `geofence_state` |
| `StorageManager+LiveActivities.swift` | `CustomerIO_LiveActivities` | `live_activity_state` |

Tests for each extension group live in the test target for the owning module, where the appropriate migration is applied before any test runs.

### Encryption Key

The passphrase passed to SqlCipher is supplied by a `DatabaseKeyProvider`, configured via `SdkConfigBuilder.databaseKeyProvider(_:)`. Two implementations are provided:

| Provider | Key source | Security model |
|----------|------------|----------------|
| `ApiKeyDatabaseKeyProvider` *(default)* | CDP API key used verbatim | File-at-rest protection; same key in every binary for a given workspace |
| `KeychainDatabaseKeyProvider` | 256-bit random key generated on first launch, stored in the platform Keychain with `kSecAttrAccessibleAfterFirstUnlock` | Per-install, hardware-bound; inaccessible even to someone with the app binary |

Both the **database filename** (`cio-<sanitizedKey>.db`) and the **Keychain account name** (`cio-db-key-<cdpApiKey>`) are scoped to the CDP API key. Rotating the API key therefore automatically produces a new database file and a new Keychain entry — the old encrypted database is orphaned without any explicit cleanup step.

### Anonymous ID Ownership

`CustomerIO` (specifically its internal `IdentityStore`) is the sole owner of the anonymous ID. On first launch, a UUID is generated and persisted to the `identity` table. It survives for the lifetime of the app install — it is never rotated except by an explicit `reset()` call. No other module generates or stores an anonymous ID.

### Migration from Previous SDK

On first launch after upgrade, the SDK runs a one-time migration pass:

1. **Identity (best-effort)**: Read `identifiedProfileId` from the legacy `UserDefaults` sandbox. If found, write to the new `identity` table and mark as migrated.
2. **Anonymous ID (best-effort)**: Read from the legacy `CioAnalytics` storage path if accessible. Write to `identity` table. If not found, generate a fresh UUID.
3. **Push token (best-effort)**: Read from legacy `GlobalDataStore` (UserDefaults). Write to `device` table.
4. **Event queue**: **Not migrated.** In-flight queued events from the old SDK are abandoned. The new SDK starts with an empty queue.
5. **Migration flag**: `sdk_meta.legacy_migration_complete = true` is set after a successful pass so it never runs again.

---

## Module Protocols

Modules may optionally conform to additional protocols that the `CustomerIO` root invokes at defined lifecycle points. The root queries the module registry for conforming modules and calls them in registration order.

### Defined Protocols

```swift
/// Called during identify(_:) just before the profile payload is uploaded.
/// The module may return additional attributes to be merged into the profile.
public protocol ProfileEnhancing: CIOModule {
    func additionalProfileAttributes(
        for profileId: String,
        existingAttributes: [String: Variant]
    ) async throws -> [String: Variant]
}
```

### Anticipated Future Protocols

These are not defined yet but the architecture should accommodate them:

| Protocol | Trigger |
|----------|---------|
| `EventIntercepting` | Before any event enters the pipeline |
| `AppLifecycleObserving` | App foreground/background transitions |
| `PushReceiving` | Incoming push notification |
| `SessionTracking` | Session start/end boundaries |

The root's module dispatcher pattern is the same for all of them: iterate `ModuleRegistry`, filter by protocol conformance, call in order, merge results where applicable.

---

## CIOTrackingClient Protocol

`CIOTrackingClient` is a narrow public protocol that abstracts the CustomerIO tracking surface:

```swift
public protocol CIOTrackingClient: AnyObject, Sendable {
    nonisolated func track(_ name: String, properties: [String: Variant])
    nonisolated func identify(_ profileId: String, traits: [String: Variant])
    nonisolated func screen(_ name: String, category: String?, properties: [String: Variant])
    nonisolated func clearIdentify()
    nonisolated func setProfileAttributes(_ traits: [String: Variant])
    nonisolated func setDeviceAttributes(_ attributes: [String: Variant])
}

extension CustomerIO: CIOTrackingClient {}
```

`CustomerIO` conforms via an empty extension — all methods already satisfy the requirements.

### Why it exists

Sub-modules (e.g. `MessagingPushModule`) need to call `track(...)` on the root SDK instance to emit metric events. Before this protocol existed, those modules held a direct `CustomerIO` reference. That made unit tests require a real configured `CustomerIO` actor, which in turn requires a real database, migrations, and the full async configure path.

With `CIOTrackingClient`, test targets can supply a simple `MockCIOTrackingClient: CIOTrackingClient` struct that records calls without any SDK infrastructure.

### What it does NOT include

- `configure(_:)` / `startConfigure(_:onCompletion:)` — async or throws; not part of the tracking surface
- `flush()` — operational, not a tracking concern for sub-modules
- `enqueueEvent(_:)` — `package` access, a separate internal seam for synthetic events; not part of the public tracking contract

### Constraints

All requirements are `nonisolated` to match `CustomerIO`'s own implementations. This means conforming types must guarantee Sendable safety themselves — the protocol does not enforce actor isolation. `CustomerIO` achieves this via `AsyncStream.Continuation.yield()`, which is synchronous and `Sendable`-safe. Mock implementations typically use simple atomic properties or accept the unchecked risk in test context.

The `AnyObject` constraint prevents value-type conformances, which would allow the protocol type to be stored as `any CIOTrackingClient` across isolation boundaries safely.

---

## Location Module

### Modes

`LocationConfig.mode` governs how the SDK obtains device coordinates. The default is `.off` — the module registers, but no location services are started and no permissions are requested.

| Mode | Behaviour |
|------|-----------|
| `.off` | Module is inert. No CLLocationManager activity, no DB writes. |
| `.manual` | SDK never requests location on its own. App calls `cio.location.setLastKnownLocation(…)` or `cio.location.requestLocationUpdate()` explicitly. |
| `.singleCapture` | One fix per continuous foreground session. Triggered on the first `UIApplication.didBecomeActive` notification after the app starts or returns from the background. Further `didBecomeActive` events in the same session are ignored. Session resets when the app enters the background. |
| `.continuous` | Ongoing monitoring via `CLLocationManager.startMonitoringSignificantLocationChanges()` — low-power, suitable for background use. |

The module never calls `CLLocationManager.requestWhenInUseAuthorization()` or `requestAlwaysAuthorization()`. If the OS has not already granted location permission, requests are silently cancelled. Permission prompts are entirely the app's responsibility.

### Storage Schema

The Location module contributes one table via `LocationStorageMigration` (migration id `002-location-schema`), encrypted by SqlCipherKit alongside the core SDK tables.

```sql
-- Single-row key/value store for precise coordinates.
-- Keys: last_lat, last_lon, last_accuracy, last_timestamp, last_uploaded_at
CREATE TABLE location_state (
    key   TEXT NOT NULL PRIMARY KEY,
    value TEXT NOT NULL
)
```

The `location_state` table stores the most recent precise fix. Coordinates in this table are what gets merged into profile traits via `ProfileEnhancing` and what is emitted in the weekly fallback upload. They are cleared on `clearIdentify()` (via `CIOEvent.ResetEvent` on the event bus).

### ProfileEnhancing — Location Attributes

`LocationModule` conforms to `ProfileEnhancing`. During every `identify(_:traits:)` call, `EventEnricher` collects the module's contribution and merges it into the outgoing traits:

```swift
[
    "latitude":  .float(lat),
    "longitude": .float(lon),
    "accuracy":  .float(acc),  // horizontal accuracy in metres
    "timestamp": .string(iso8601),
]
```

If no coordinates are stored (e.g. mode is `.off`, or `clearIdentify()` was called), the module returns an empty dictionary and identify proceeds without location traits.

Every time `currentLocationAttributes()` is called and returns non-empty data, it also stamps `last_uploaded_at` in `location_state`. This timestamp resets the weekly fallback timer.

### Weekly Fallback Upload

Location-only apps — where users are identified infrequently — might go weeks without an `identify` call, so location data would never reach the backend via `ProfileEnhancing`. The weekly fallback exists to bridge this gap.

After every location update is recorded, `LocationCoordinator` checks whether the configured upload interval has elapsed since `last_uploaded_at`. If it has (defaulting to 7 days), the coordinator synthesises a `track("location_update", …)` event with the same lat/lon/accuracy/timestamp payload and yields it to the pipeline via `root.enqueueEvent(.track("location_update", props))`.

The upload interval is configurable from the backend: if a value is stored in `location_state` under the key `upload_interval_seconds`, it overrides the 7-day default. This allows the aggregation engine's remote config to tune the interval without an app update. The `RemoteConfigUpdatedEvent` pattern on the event bus is the intended delivery mechanism (not yet implemented in the aggregation engine).

Fallback upload does **not** bypass the aggregation engine — the synthesised event flows through the full pipeline like any other `track()` call and may be aggregated, counted, or discarded according to the active ruleset.

---

## Screen Tracking

### UIKit (Swizzle-Based, Opt-In)

UIKit swizzle-based auto-tracking is preserved from the existing SDK, isolated to a single file, and guarded by `#if canImport(UIKit)`. The swizzle intercepts `UIViewController.viewDidAppear(_:)` and bridges back into the `CustomerIO` actor via a `Task` — never a direct synchronous call from swizzled context.

Opt-in at configuration time:

```swift
let config = SdkConfigBuilder(cdpApiKey: "…")
    .autoTrackScreenViews(true)  // off by default
    .build()
```

### SwiftUI ViewModifier

A `cio_trackScreen(_:category:)` modifier is provided for SwiftUI views. The `cio_` prefix is intentional — it namespaces the method against the many similar modifiers that different analytics SDKs tend to add to `View`, where naming collisions are a known problem in mixed-SDK projects.

The modifier requires an explicit screen name string. Auto-deriving the name from the Swift type via `String(describing: Self.self)` is deliberately not provided as a primary API — type names are compiler-internal identifiers that can change silently across refactors without breaking the build.

#### Avoiding Static Globals via SwiftUI Environment

Rather than reaching for a static `CustomerIO.shared`, the modifier reads the `CustomerIO` instance from SwiftUI's environment. The app injects it once at the root view:

```swift
// App root:
@main
struct MyApp: App {
    let cio = CustomerIO()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.customerIO, cio)
        }
    }
}

// Any view, anywhere in the hierarchy:
MyDetailView()
    .cio_trackScreen("Product Detail", category: "Commerce")
```

The `CustomerIO` environment key is defined in the `CustomerIO` module:

```swift
// CustomerIO/ScreenTracking/CustomerIOEnvironmentKey.swift
private struct CustomerIOEnvironmentKey: EnvironmentKey {
    static let defaultValue: CustomerIO? = nil
}

extension EnvironmentValues {
    public var customerIO: CustomerIO? {
        get { self[CustomerIOEnvironmentKey.self] }
        set { self[CustomerIOEnvironmentKey.self] = newValue }
    }
}
```

The modifier and `View` extension:

```swift
// CustomerIO/ScreenTracking/ScreenTrackingModifier.swift
struct CIOScreenTrackingModifier: ViewModifier {
    let screenName: String
    let category: String?

    @Environment(\.customerIO) private var customerIO

    func body(content: Content) -> some View {
        content.onAppear {
            customerIO?.screen(screenName, category: category)
        }
    }
}

// CustomerIO/ScreenTracking/View+CIOTrackScreen.swift
extension View {
    public func cio_trackScreen(_ name: String, category: String? = nil) -> some View {
        modifier(CIOScreenTrackingModifier(screenName: name, category: category))
    }
}
```

`screen()` on `CustomerIO` is `nonisolated` (see Actor Concurrency Model), so calling it from `onAppear`'s `@MainActor` context requires no `await` and crosses no actor boundary.

#### Testing and Xcode Previews

Inject a real or mock `CustomerIO` via the environment key:

```swift
MyView()
    .environment(\.customerIO, mockCIO)
```

If no instance is injected, the modifier silently no-ops (`customerIO` is `nil` by default) — safe for test targets and Previews that don't configure the full SDK.

---

## Actor Concurrency Model

| Type | Concurrency | Rationale |
|------|-------------|-----------|
| `CustomerIO` | `actor` | Owns configuration and pipeline state; event methods are `nonisolated` |
| `ModuleRegistry` | `actor` | Concurrent-safe module storage |
| `AggregationEngine` | `actor` | Mutable accumulator state |
| `EventQueue` | `actor` | Serialized queue operations |
| `UploadScheduler` | `actor` | Coordinates batch assembly and upload |
| `StorageManager` | `struct` (`Sendable`) | Stateless gateway; thread safety delegated to `Database` actor |
| `CommonEventBus` | `Sendable` class (existing) | Internal operation queue |
| Module implementations | `actor` | Each module owns its state |
| `Synchronized<T>` | `@unchecked Sendable` class | Bridge for legacy/non-Sendable values |

### nonisolated Event Methods and AsyncStream

`CustomerIO` is a plain `actor`, not `@MainActor`. Event-tracking methods (`track`, `identify`, `screen`) are `nonisolated` — they can be called from any thread or isolation domain without an actor hop and without `await`.

Internally, these methods yield into an `AsyncStream<PendingEvent>` via a `nonisolated let` continuation. `AsyncStream.Continuation.yield()` is synchronous and `Sendable`-safe. An actor-isolated processing loop task consumes the stream for the lifetime of the actor.

```swift
public actor CustomerIO {
    private nonisolated let _events: AsyncStream<PendingEvent>.Continuation
    private let eventStream: AsyncStream<PendingEvent>

    public init() {
        (eventStream, _events) = AsyncStream.makeStream(
            of: PendingEvent.self,
            bufferingPolicy: .bufferingOldest(100) // oldest preserved, newest dropped if full
        )
        // Kicks off internal processing loop Task
    }

    // Callable from any thread, any isolation domain, before or after configure().
    // No await, no actor hop, no throwing.
    public nonisolated func track(_ name: String, properties: [String: Variant] = [:]) {
        _events.yield(.track(name, properties))
    }

    public func configure(_ config: SdkConfig) async throws {
        // Build container, initialize modules, load aggregation rules...
        // Flip internal configured flag — processing loop begins draining the stream.
    }
}
```

This design also resolves the pre-configuration buffering problem. Events yielded before `configure()` completes sit in the stream's internal buffer (capped at 100, oldest-first). The processing loop suspends until the configured flag is set, then drains the buffer in order. No separate two-mode buffer logic is needed — the stream IS the buffer.

If `configure()` throws, the stream is terminated and buffered events are silently discarded. `yield()` returns `.terminated` in subsequent calls, which the `nonisolated` methods ignore.

Modules that need to interact with UIKit or SwiftUI (e.g. `MessagingInApp`) dispatch to `@MainActor` internally — the root actor does not need to be `@MainActor` to support this.

---

## Package Distribution

The SDK is distributed via **Swift Package Manager only**. The absence of a Podspec is a deliberate architectural decision, not an omission.

CocoaPods has been officially deprecated and the trunk repository will become read-only in fall 2026. Publishing new versions to CocoaPods would require maintaining `.podspec` files and a parallel distribution path with no long-term future. The maintenance cost is not justified.

### Wrapper SDK Compatibility

- **Flutter**: SPM plugin support has been available since Flutter 3.19 (early 2024). The CIO Flutter wrapper plugin declares its iOS native dependency via a `Package.swift`. No Podfile required.
- **Expo**: Expo Modules API supports SPM for native modules. EAS Build handles resolution.
- **React Native (bare)**: RN's iOS build system remains CocoaPods-centric at the framework level as of this writing. This is the community's problem to solve — CocoaPods deprecation affects every major iOS library, not just CIO, and a solution will be forced before the trunk locks. The CIO SDK ships via SPM; if the RN wrapper temporarily requires a pre-built binary bridge (e.g. via `swift-create-xcframework`), that is the wrapper team's concern and does not affect the SDK's distribution model.

---

## Package Structure

```
Sources/
  CustomerIO_Utilities/     # Internal; not a public library product
    DI/
      DependencyContainer.swift
      Resolver.swift
      Autoresolvable.swift
      DefaultInitializable.swift
    Synchronized/
      Synchronized.swift
      Synchronized+*.swift
    Variant/
      Variant.swift
      VariantConvertible.swift
      *+VariantConvertible.swift
    EventBus/
      CommonEventBus.swift
      RegistrationToken.swift
    Storage/
      StorageManager.swift         # struct; SqlCipher-backed; package-level db property
      MigrationRunner.swift
    Networking/
      HttpClient.swift
      HttpRequestRunner.swift
    Util/
      Logger.swift
      DateUtil.swift
      JsonAdapter.swift
    QuadKey.swift                  # lat/lon → QuadKey string at configurable zoom

  CustomerIO/               # Root public module
    CustomerIO.swift             # actor; configure(_:); identify/track/screen
    CIOTrackingClient.swift      # protocol; narrow tracking surface + CustomerIO conformance
    SdkConfig.swift              # struct
    SdkConfigBuilder.swift       # builder
    ModuleRegistry.swift         # actor
    Module/
      CIOModule.swift            # protocol
      ProfileEnhancing.swift     # protocol
    Pipeline/
      EventEnricher.swift
      EventProcessor.swift       # struct; per-event dispatch logic; closure-injected collaborators
      EventQueue.swift           # actor
      UploadScheduler.swift      # actor
      BatchAssembler.swift
    Aggregation/
      AggregationEngine.swift    # actor
      AggregationRule.swift
      AggregationConfig.swift
    Storage/
      StorageManager+EventQueue.swift    # extension: event_queue methods
      StorageManager+Aggregation.swift   # extension: aggregation_rules/state methods
    Store/
      IdentityStore.swift
      DeviceStore.swift
    ObjC/
      CIOBridge.swift             # NSObject facade; @objc methods only
    ScreenTracking/
      AutoTrackingSwizzle.swift  # UIKit swizzle; #if canImport(UIKit)
      CustomerIOEnvironmentKey.swift
      ScreenTrackingModifier.swift
      View+CIOTrackScreen.swift

  Location/
    Config/
      LocationConfig.swift         # LocationMode enum + LocationConfig struct
      SdkConfigBuilder+Location.swift  # .location(_:) builder extension
    AppLifecycleObserver.swift     # UIApplication notifications → AsyncStream
    CoreLocationProvider.swift     # CLLocationManager actor (#if os(iOS))
    CustomerIO+Location.swift      # extension: cio.location accessor
    LocationCoordinator.swift      # actor: modes, coordinate recording, ProfileEnhancing
    LocationModule.swift           # CIOModule + ProfileEnhancing + MigrationProviding
    LocationProvider.swift         # @MainActor & Sendable protocol
    LocationStorageMigration.swift # Migration: location_state

  Geofencing/
    Config/
      GeofenceConfig.swift              # GeofenceMode enum + GeofenceConfig struct
      SdkConfigBuilder+Geofencing.swift # .geofencing(_:) builder extension
    CustomerIO+Geofencing.swift         # extension: cio.geofencing accessor
    GeofenceCoordinator.swift           # @MainActor: CLLocationManager, candidate selection
    GeofenceLoader.swift                # loads bundle-seeded JSON dataset
    GeofenceSyncClient.swift            # cursor-based server sync (GEOFENCING.md protocol)
    GeofenceStorageMigration.swift      # Migration: geofences + geofence_state
    Geofence.swift                      # value type returned to onGeofenceEntered/Exited
    GeofencingModule.swift              # CIOModule + MigrationProviding
    StorageManager+Geofences.swift      # extension: geofences + geofence_state methods

  MessagingPush/                 # replaces former MessagingPushAPN + MessagingPushFCM targets
    PushTokenProvider.swift      # protocol + APNPushProvider (SDK-supplied APN implementation)
    PushConfig.swift             # PushConfig struct
    PushConfigBuilder.swift      # fluent builder; .forExtension factory for NSE use
    SdkConfigBuilder+Push.swift  # .push { } extension
    MessagingPushModule.swift    # CIOModule actor; cio.push entry point
    MessagingPushExtension.swift # NSE entry point (MessagingPushExtension class)
    CustomerIO+Push.swift        # extension: cio.push accessor → MessagingPushModule
    PushHandling/                # (to be implemented)
      PushNotificationCenterRegistrar.swift
      PushEventHandler.swift
      PushEventHandlerProxy.swift
      iOSPushEventListener.swift
      PushClickHandler.swift
      PushHistory.swift
    Type/                        # (to be implemented)
      PushNotification.swift
      PushNotificationAction.swift
      CustomerIOParsedPushPayload.swift
      UNNotificationWrapper.swift
    Extension/                   # (to be implemented)
      ExtensionDeliveryQueue.swift   # App Group file queue (primary delivery path)
      ExtensionDeliveryUploader.swift # background URLSession fallback

  MessagingInApp/
    MessagingInAppModule.swift
    CustomerIO+MessagingInApp.swift

  LiveActivities/               # iOS 16.1+ only; entire module gated #if os(iOS)
    Config/
      LiveActivityConfig.swift         # LiveActivityConfig struct
      SdkConfigBuilder+LiveActivities.swift  # .liveActivities(_:) builder extension
    CustomerIO+LiveActivities.swift    # extension: cio.liveActivities accessor
    LiveActivitiesModule.swift         # actor; token observation task management
    LiveActivityStorageMigration.swift # Migration: live_activity_state table
    StorageManager+LiveActivities.swift # extension: live_activity_state methods
```

---

## Live Activities Module

Full design specification: `LIVEACTIVITIES.md`.

`LiveActivitiesModule` gives the CIO backend visibility into activity push tokens so campaigns and automations can drive Live Activity updates via Apple's ActivityKit push-to-update API. The module operates entirely at the token and lifecycle level; it never reads or renders `ContentState`.

### Platform Gating

The entire module is wrapped in `#if os(iOS)`. ActivityKit is unavailable on macOS, watchOS, and tvOS. All public API is additionally annotated `@available(iOS 16.1, *)`. The `cio.liveActivities` accessor is unavailable at the type level on non-iOS platforms.

### Type Erasure

`Activity<T>` is generic over the app's concrete `ActivityAttributes` type, which the SDK does not know at compile time. The public API accepts `AsyncStream<Data>` (forwarded from `activity.pushTokenUpdates`) and plain `String` identifiers. The app owns the `Activity<T>` instance and bridges the async sequence to the SDK.

### Token Observation

The module maintains one internal `Task<Void, Never>` per tracked activity, keyed by `activityId` in a `[String: Task<Void, Never>]` dictionary. Each task iterates the forwarded `AsyncStream<Data>`, hex-encodes new tokens, compares them to the stored value, and uploads a registration event on change. When the stream ends (activity expired), the task automatically calls `activityDidEnd(activityId:)` if not already called.

On `ResetEvent` (user logout / `clearIdentify()`), all tasks are cancelled, the dictionary is cleared, and all rows in `live_activity_state` are deleted.

### Storage

`LiveActivityStorageMigration` (migration id `005-live-activity-schema`) adds a `live_activity_state` table. Token and metadata persistence is handled by `StorageManager+LiveActivities.swift`, following the extension pattern used by all other modules.

### Wire Format

Activity token registrations and lifecycle events are submitted as standard `track` events. Provisional event names are `"Live Activity Token Registered"` and `"Live Activity Ended"` — exact names and payload shape to be confirmed with the backend team before implementation. See `LIVEACTIVITIES.md` → Token Registration Wire Format.

---

## Firebase Integration

The `MessagingPush` module has **no direct dependency on Firebase**. This is a deliberate design decision, not an omission.

Apps using Firebase implement the `PushTokenProvider` protocol by wrapping their own `Firebase.Messaging` instance:

```swift
class MyFirebaseWrapper: PushTokenProvider {
    let messaging: Messaging  // app's own Firebase.Messaging instance

    func tokenFromAPNSData(_ deviceToken: Data) async throws -> String? {
        await messaging.setAPNSToken(deviceToken)
        return await messaging.fcmToken  // nil → will arrive via observeTokenRefresh
    }

    func observeTokenRefresh(_ handler: @Sendable @escaping (String) -> Void) async {
        messaging.onTokenRefresh(handler)
    }
}

// Configuration:
SdkConfigBuilder(cdpApiKey: "…")
    .push { PushConfigBuilder(provider: MyFirebaseWrapper()) }
    .build()
```

`MessagingPushModule` only ever sees the `PushTokenProvider` protocol. Firebase itself can be installed via SPM, a pre-built XCFramework, or any future distribution mechanism — the SDK is indifferent.

### Consequences

- Apps that already use Firebase are not double-loading it through the SDK.
- The `PushTokenProvider` conformance is trivially mockable in tests with no Firebase dependency in the test target.
- If Firebase changes its token delivery API, only the app's thin wrapper adapts; the SDK module is unchanged.
- `CustomerIO_MessagingPush` has no SPM dependency on `firebase-ios-sdk` and never will.
- APN apps (`APNPushProvider`) incur no binary overhead from Firebase paths — there is no Firebase code in the SDK at all, not even unreachable branches.

---

## Objective-C Compatibility

The main `CustomerIO` type is pure Swift (plain `actor`, `async throws`) and is not `@objc`-compatible. A thin `CIOBridge` facade class exposes a minimal surface for mixed-codebase and ObjC-only call sites.

`CIOBridge` is a plain `NSObject` subclass with `@objc`-annotated methods. Each method dispatches fire-and-forget into a `Task` on the Swift side. Properties passed as `NSDictionary` are converted to `[String: Variant]` inside the bridge. No completion handlers are exposed — tracking calls are best-effort by nature.

### Exposed Surface

| ObjC Method | Notes |
|-------------|-------|
| `trackEvent:` / `trackEvent:properties:` | `properties` is `NSDictionary *` |
| `identify:` / `identify:traits:` | `traits` is `NSDictionary *` |
| `screenView:` / `screenView:properties:` / `screenView:category:` / `screenView:category:properties:` | `category` is `NSString *`; `properties` is `NSDictionary *` |
| `clearIdentify` | Logout / profile reset |
| `flush` | Explicit upload trigger; useful in notification extensions |
| `isConfigured` | `BOOL` property; safe to poll from ObjC without async |

### What Stays Swift-Only

- `configure(_:)` and all initialization — `async throws` is not bridgeable
- Module accessors (`.location`, `.push`, etc.)
- All aggregation, pipeline, and storage internals
- Any method with typed `async throws` return values

The wrapper SDKs (React Native, Flutter, Cordova) do not require ObjC compatibility — they call into the Swift API from their own Swift plugin layer.

---

## Open Questions

- **`screen()` method signature**: Resolved. `category` is a first-class field on the screen event envelope (matching the Segment spec used by the old SDK), not folded into the `properties` bag. The full signature is `screen(_ name: String, category: String? = nil, properties: [String: Variant] = [:])`. The UIKit auto-tracking swizzle omits category because it cannot be inferred from a `UIViewController`; the SwiftUI ViewModifier exposes it explicitly. The ObjC bridge exposes `screenView:category:properties:`. Server-side payloads are structurally identical to explicit `screen()` calls in the old SDK.

- **`configure()` throw conditions**: In fire-and-forget mode (`Task { try await cio.configure(config) }`), a thrown error silently terminates the event stream and the SDK does nothing, with no feedback to the developer. What are the actual conditions under which `configure()` throws (invalid API key format? failed initial network fetch?)? Should the SDK log a fatal diagnostic when it throws in fire-and-forget mode, or is silent termination acceptable?

### Resolved

- **Platform targets**: iOS 13+ is maintained. The only OS-version-gated API in the new design is `URLSession`'s async methods (iOS 15+). The HTTP client must wrap the completion-handler `URLSession` API in a `withCheckedContinuation` call for iOS 13/14 compatibility. All actor concurrency, `DependencyContainer`, `Synchronized`, and `Variant` types are available on iOS 13 via the Swift 5.5+ embedded runtime. `os.Logger` structured logging (iOS 14+) and `Clock`/`ContinuousClock` (iOS 16+) are not used; flush timing relies on lifecycle events instead.
- **Aggregation config endpoint**: Static path relative to the region base URL. Exact path TBD; defined in one constant. No user-configurable refresh interval — fetched on startup and app foreground, but no more than once per 24 hours (last fetch timestamp persisted to `sdk_meta`).
- **Flush schedule granularity**: Schedule values in rule configs are minimum durations ("no sooner than"). Flush checks only occur at app lifecycle events (startup, foreground, background). No background timers.
- **Anonymous ID ownership**: `CustomerIO`/`IdentityStore` owns and generates the anonymous ID (UUID on first launch, persisted forever unless `reset()` is called). Migration attempts to recover the legacy analytics-swift anonymous ID as best-effort.
