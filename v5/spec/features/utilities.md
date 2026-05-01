# CustomerIO_Utilities — Feature Specification

**Status:** Implemented
**Last updated:** April 29, 2026

---

## Overview

`CustomerIO_Utilities` is an internal Swift package target — not a public library
product — that provides shared infrastructure consumed by the `CustomerIO` root
module and all feature modules. App developers never import it directly.

Because it sits at the bottom of the dependency graph, `CustomerIO_Utilities`
must have no knowledge of SDK-level concepts (events, profiles, modules). It
contains only general-purpose primitives that could plausibly live in any
Swift project.

---

## What Does Not Live Here

`DatabaseKeyProvider`, `ApiKeyDatabaseKeyProvider`, and `KeychainDatabaseKeyProvider`
are defined in the `CustomerIO` module (`Sources/CustomerIO/Storage/`), not here.
Although they are infrastructure, they are part of the public `SdkConfigBuilder`
API and must be referenceable by app code that imports only `CustomerIO`. Moving
them here would make them inaccessible to app developers since
`CustomerIO_Utilities` is not a library product.

---

## Design Constraints

- No SDK-level types may be imported here. `CustomerIO_Utilities` must remain a
  leaf dependency.
- All types must be `Sendable` or explicitly `@unchecked Sendable` with
  documented isolation guarantees.
- No static state. Every type is instantiated and injected; nothing is accessed
  via a global or singleton.

---

## Components

### `Synchronized<T>`

**File:** `Synchronized/Synchronized.swift` and extensions

A thread-safe wrapper for any value type, backed by `NSRecursiveLock`. Declared
`@unchecked Sendable` because it enforces its own invariants rather than relying
on Swift's type system.

```swift
public final class Synchronized<T>: @unchecked Sendable {
    public var wrappedValue: T { get set }          // lock-protected
    public func mutating<R>(_ body: (inout T) throws -> R) rethrows -> R
    public func mutatingAsync<R>(_ body: @Sendable (inout T) throws -> sending R) async throws -> R
    public func using<R>(_ body: (T) throws -> R) rethrows -> R
    public func usingAsync<R>(_ body: @Sendable (T) throws -> sending R) async throws -> R
    public func atomicSetAndFetch(_ newValue: T) -> T
}
```

**Why `NSRecursiveLock`:** The SDK occasionally acquires the same lock from a
re-entrant call path (e.g. an observer registered inside a `mutating` closure
during early initialisation). A non-recursive lock would deadlock in those cases.

**Extension files** add conditional conformances and convenience operators for
common wrapped types: `Arithmetic`, `Bool`, `Comparable`, `Equatable`,
`Hashable`, `Collections`, `Dictionaries`.

---

### `CommonEventBus` / `EventBus`

**Files:** `EventBus/CommonEventBus.swift`, `EventBus/RegistrationToken.swift`

A type-erased publish/subscribe bus. Events are any `Sendable` value. Observers
register a typed closure; the bus filters by dynamic type cast at delivery time.

```swift
public protocol EventBus: Sendable {
    func registerObserver<EventType: Sendable>(
        listener: @Sendable @escaping (EventType) -> Void
    ) -> RegistrationToken<UUID>
    func post(_ event: any Sendable)
}
```

**Delivery:** `post()` takes a snapshot of current observers synchronously, then
dispatches `NotifyOperation` instances onto a background `OperationQueue`
asynchronously. Observers that do not match the event type return `false` and
are counted but not invoked. After all notifications complete, a
`DeliverySummary` system message is posted (not recursed into).

**`postAndWait`:** An async variant that suspends until all observers finish
processing. Used in tests and in places where ordering guarantees are needed.

**`RegistrationToken<UUID>`:** Returned by `registerObserver`. Holds a `deinit`
cleanup closure that removes the observer when the token is released. Modules
store the token as a `private var` for the lifetime of the object — dropping it
unregisters automatically.

**SDK-level event types** (defined in `CustomerIO`, not here):
`ProfileIdentifiedEvent`, `AnonymousProfileIdentifiedEvent`,
`ScreenViewedEvent`, `ResetEvent`.

---

### `StorageManager`

**Files:** `Storage/StorageManager.swift` and module-specific extensions

A `struct` (stateless, `Sendable`) gateway to the encrypted SQLite database.
Thread safety is fully delegated to `Database` (a SqlCipherKit `actor`).

The `db: Database` property is `package` access, allowing extension files in
other targets within this Swift package to add typed query methods without
making the raw database handle part of the public API.

**Core methods:**

| Method | Purpose |
|---|---|
| `runMigrations(extra:)` | Apply `CreateSDKSchema` plus any module-supplied migrations. Must be called once before any other method. |
| `getString(_:from:)` / `setString(_:for:in:)` | Generic key/value read/write for any table with `(key TEXT, value TEXT)` shape. |
| `getMetaValue(_:)` / `setMetaValue(_:for:)` | Convenience wrappers targeting the `sdk_meta` table. |

**Core schema (`CreateSDKSchema`, migration id `001`):**

| Table | Purpose |
|---|---|
| `identity` | Profile ID and anonymous ID |
| `device` | Push token and device attributes |
| `event_queue` | Pending upload events (JSON-serialised `EnrichedEvent`) |
| `aggregation_rules` | Cached server aggregation ruleset (single row) |
| `aggregation_state` | In-progress accumulator values per rule |
| `sdk_meta` | SDK flags, version, migration markers |

---

### `MigrationRunner`

**File:** `Storage/MigrationRunner.swift`

Runs a one-time migration from the legacy SDK on first launch after upgrade.
Reads `UserDefaults` keys used by the previous SDK, returns them as `LegacySeeds`,
and marks completion in `sdk_meta` so it never runs again.

```swift
public actor MigrationRunner {
    public nonisolated func legacySeeds() -> LegacySeeds
    public func markComplete() async throws
    public func isComplete() async -> Bool
}

public struct LegacySeeds: Sendable {
    public let profileId: String?
    public let anonymousId: String?
    public let pushToken: String?
}
```

`legacySeeds()` is `nonisolated` because it only reads `UserDefaults` — no
actor-isolated state is touched. The caller is responsible for writing the seeds
to the appropriate stores (e.g. `IdentityStore`, `DeviceStore`).

---

### `MigrationProviding`

**File:** `Storage/MigrationProviding.swift`

Protocol for modules that need to extend the database schema. The
`CustomerIO` root collects `additionalMigrations` from all registered
`MigrationProviding` modules and passes them to `StorageManager.runMigrations(extra:)`
before any module's `configure()` is called.

```swift
public protocol MigrationProviding {
    var additionalMigrations: [any Migration] { get }
}
```

Migration types (`GeofenceStorageMigration`, `LocationStorageMigration`) are
`internal` to their module. They escape only as `any Migration` existentials
through this property.

---

### `CIOKeys`

**Files:** `Keys/CIOKeys.swift` and module-specific extensions

Namespace for all string constants (storage keys, table names, event names,
payload header names) used across the SDK. Prevents magic strings from being
scattered as inline literals.

- The root `public enum CIOKeys` lives in `Keys/CIOKeys.swift`.
- Constants shared between two or more modules are added to extensions in
  `Keys/` (e.g. `CIOKeys+Storage.swift`).
- Constants that belong entirely within one module are declared in an `internal`
  extension in that module's own `Keys/` subdirectory.
- Constants are organised by **intended use**, not by value.

---

### `HttpClient` / `HttpRequestRunner`

**Files:** `Networking/HttpClient.swift`, `Networking/HttpRequestRunner.swift`

```swift
public protocol HttpClient: Sendable {
    func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse)
}
```

`HttpRequestRunner` is the `URLSession`-backed production implementation.
It wraps the completion-handler `dataTask(with:)` API in a
`withCheckedThrowingContinuation` for iOS 13/14 compatibility
(`URLSession.data(for:)` requires iOS 15+).

Inject a mock `HttpClient` in tests. Register `HttpRequestRunner` in production.

---

### `JsonAdapter`

**File:** `Util/JsonAdapter.swift`

Thin wrapper around `JSONEncoder` / `JSONDecoder` with ISO 8601 date strategy
configured by default. Provides `encode<T: Encodable>` and
`decode<T: Decodable>` with consistent error behaviour across the SDK.

---

### `QuadKey`

**File:** `QuadKey.swift`

Encodes WGS-84 coordinates to the Bing Maps quadtree tile string format.

```swift
public enum QuadKey {
    public static let defaultZoom: Int = 13

    /// Encodes a coordinate pair to a QuadKey string at the given zoom level.
    public static func encode(latitude: Double, longitude: Double, zoom: Int = defaultZoom) -> String

    /// Returns the 9-tile Moore neighbourhood (centre + 8 neighbours) for a coordinate.
    public static func neighborhoodTiles(latitude: Double, longitude: Double, zoom: Int = defaultZoom) -> [String]
}
```

At zoom 13, each tile covers approximately 4.9 km × 4.9 km at the equator,
scaling down by cos(latitude) at higher latitudes (~3.5 km at 45°N).

Used exclusively by `GeofencingModule` for candidate selection and indexing.
Lives in `CustomerIO_Utilities` so both the Geofencing module and its test
target can access it without a cross-module import.

---

### `Logger` / `DateUtil`

**Files:** `Util/Logger.swift`, `Util/DateUtil.swift`

Thin wrappers over `swift-log`'s `Logger` type and `Date`/`ISO8601DateFormatter`
respectively. `DateProviding` is a protocol for injecting a fixed date in tests
(used by `EventEnricher` tests).
