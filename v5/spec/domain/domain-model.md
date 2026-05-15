# CustomerIO iOS SDK — Domain Model

---

## Module Graph

```
┌──────────────────────────────────────────────────────────┐
│                   CustomerIO_Utilities                    │
│  (internal — never imported directly by app developers)  │
│                                                          │
│  Synchronized                                             │
│  CommonEventBus · RegistrationToken                      │
│  HttpClient · JsonAdapter · DateUtil                     │
│  StorageManager · MigrationRunner                        │
│  CIOKeys                                                 │
└─────────────────────────┬────────────────────────────────┘
                          │ (internal dependency)
           ┌──────────────▼──────────────────┐
           │          CustomerIO              │
           │  (root public module)            │
           │                                 │
           │  Variant / VariantConvertible    │
           │  CIOTrackingClient               │
           │  identify · track · screen       │
           │  Event pipeline                 │
           │  Aggregation engine             │
           │  Upload scheduler               │
           │  SdkConfig / SdkConfigBuilder   │
           │  StorageManager extensions      │
           │  Module registry                │
           │  CIOLogger / CIOLogLevel        │
           └──┬──────────┬──────────┬────────┘
              │          │          │
  ┌───────────▼──┐  ┌────▼────────────────┐  ┌────────────────────┐  ┌──────────────────────┐
  │  Location    │  │  MessagingPush       │  │  MessagingInApp    │  │  LiveActivities      │
  │  module      │  │  (APN or FCM via     │  │  (not yet impl.)   │  │  (iOS 16.1+ only)    │
  │              │  │  PushTokenProvider)  │  │                    │  │  (not yet impl.)     │
  └──────────────┘  └──────────────────────┘  └────────────────────┘  └──────────────────────┘
        │
  ┌─────▼──────────┐
  │   Geofencing   │
  │   module       │
  └────────────────┘
```

`CustomerIO_Utilities` is the successor to `CioInternalCommon`. Its products are
**not** exposed as a public library product. Sub-modules depend on it internally.
App code never imports it directly.

---

## Event Pipeline

```
track / identify / screen / clearIdentify / setProfileAttributes / setDeviceAttributes
        │  (nonisolated — callable from any thread; yields to AsyncStream)
        ▼
  [Enrichment Stage]   EventEnricher actor
  • Timestamp, anonymousId
  • Profile ID from IdentityStore
  • ProfileEnhancing module contributions merged into identify payloads
        │
        ▼
  [Aggregation Stage]  AggregationEngine actor
  • .passThrough → event continues
  • .aggregated  → absorbed into accumulator (not queued)
  • .discarded   → silently dropped
        │ (.passThrough only)
        ▼
  [Event Queue]        EventQueue actor  (SqlCipher-encrypted event_queue table)
        │
        ▼
  [Upload Scheduler]   UploadScheduler actor
  • Batch assembler (count- or byte-triggered)
  • HTTP POST to CDP API
  • Retry with exponential backoff
  • Delete from queue on server acknowledgement
```

**Pre-configure buffering:** Events yielded before `configure()` completes sit in
the `AsyncStream`'s internal buffer (capped at 100, oldest-first). The processing
loop suspends until configuration is complete, then drains in order. No separate
two-mode buffer logic is needed.

**`trackSynthesized` bypass:** Events emitted internally by the SDK (flush events
from `AggregationEngine`, `"Device Deleted"` from `unregisterDevice()`) use the
`.trackSynthesized` case. These skip the aggregation evaluation stage and go
directly to enrichment → queue → upload.

---

## Storage Schema

All data is written to an encrypted SqlCipher database. `UserDefaults` and flat-file
JSON are not used.

| Table | Module | Contents |
|-------|--------|----------|
| `identity` | `CustomerIO` | Current profile ID, anonymous ID |
| `device` | `CustomerIO` | Push token, device attributes |
| `event_queue` | `CustomerIO` | Pending upload events (`Variant`-serialized) |
| `aggregation_rules` | `CustomerIO` | Cached server aggregation rule config |
| `aggregation_state` | `CustomerIO` | In-progress accumulator values |
| `sdk_meta` | `CustomerIO` | SDK version, install date, migration flags |
| `location_state` | `Location` | Last known coordinates and upload timestamp |
| `geofences` | `Geofencing` | Geofence definitions from server sync |
| `geofence_state` | `Geofencing` | Current monitoring cursor and active regions |
| `live_activity_state` | `LiveActivities` | Active Live Activity tokens and metadata |

### StorageManager Extension Pattern

`StorageManager` is a `struct` in `CustomerIO_Utilities`. Module-specific query methods
live in `extension StorageManager` files inside their owning module:

| File | Module | Tables |
|------|--------|--------|
| `StorageManager+EventQueue.swift` | `CustomerIO` | `event_queue` |
| `StorageManager+Aggregation.swift` | `CustomerIO` | `aggregation_rules`, `aggregation_state` |
| `StorageManager+Push.swift` | `MessagingPush` | `device` (push token) |
| `StorageManager+Geofences.swift` | `Geofencing` | `geofences`, `geofence_state` |
| `StorageManager+LiveActivities.swift` | `LiveActivities` | `live_activity_state` |

### Encryption Key

| Provider | Key source | Security model |
|----------|------------|----------------|
| `ApiKeyDatabaseKeyProvider` *(default)* | CDP API key used verbatim | File-at-rest protection only |
| `KeychainDatabaseKeyProvider` | 256-bit random key, generated on first launch, stored in Keychain with `kSecAttrAccessibleAfterFirstUnlock` | Per-install, hardware-bound |

The database filename (`cio-<sanitizedKey>.db`) and Keychain account name
(`cio-db-key-<cdpApiKey>`) are both scoped to the CDP API key. Rotating the
API key automatically produces a new database and Keychain entry.

---

## Concurrency Model

| Type | Concurrency | Rationale |
|------|-------------|-----------|
| `CustomerIO` | `actor` | Owns configuration and pipeline state; event methods are `nonisolated` |
| `ModuleRegistry` | `actor` | Concurrent-safe module storage |
| `AggregationEngine` | `actor` | Mutable accumulator state |
| `EventQueue` | `actor` | Serialized queue operations |
| `UploadScheduler` | `actor` | Coordinates batch assembly and upload |
| `StorageManager` | `struct` (`Sendable`) | Stateless gateway; thread safety delegated to `Database` actor |
| `CommonEventBus` | `Sendable` class | Internal operation queue; no logging |
| Module implementations | `actor` | Each module owns its mutable state |
| `Synchronized<T>` | `@unchecked Sendable` | Bridge for nonisolated access to actor-owned state |

### nonisolated Event Methods

Event-tracking methods (`track`, `identify`, `screen`, etc.) are `nonisolated`.
They yield into an `AsyncStream<PendingEvent>` via a `nonisolated let` continuation.
`AsyncStream.Continuation.yield()` is synchronous and `Sendable`-safe. An
actor-isolated processing loop task consumes the stream for the SDK's lifetime.

---

## Module Startup Phases

```swift
public protocol CIOModule: AnyObject, Sendable {
    nonisolated func preActivate(_ config: SdkConfig)   // Phase 1 — synchronous
    func configure(_ config: SdkConfig, storage: StorageManager, root: CustomerIO) async throws  // Phase 2
}
```

| Phase | When | Who overrides |
|-------|------|---------------|
| `preActivate` | Before first run-loop cycle; inside `activateModulesForLaunch` | Only `MessagingPushModule` (registers `UNUserNotificationCenter` delegate) |
| `configure` | After database and pipeline are ready | All modules |

Modules access the event bus via `root.eventBus` — a `nonisolated package let`
readable from any context without `await`. It is not passed as a separate parameter.

---

## Anonymous ID Ownership

`CustomerIO` (via its internal `IdentityStore`) is the sole owner of the anonymous
ID. On first launch, a UUID is generated and persisted to the `identity` table.
It survives for the lifetime of the app install — it is never rotated except by an
explicit `clearIdentify()` call. No other module generates or stores an anonymous ID.

---

## SDK-Internal Event Bus

`CommonEventBus` is used for cross-module communication within the SDK only.
App code does not interact with it. Events posted on the bus:

| Event | Poster | Subscribers |
|-------|--------|-------------|
| `ProfileIdentifiedEvent` | `CustomerIO.identify()` | `MessagingInApp` (engine profile token) |
| `AnonymousProfileIdentifiedEvent` | `CustomerIO.identify()` | `MessagingInApp` (engine anonymous ID) |
| `ScreenViewedEvent` | `CustomerIO.screen()` | `MessagingInApp` (trigger matching) |
| `ResetEvent` | `CustomerIO.clearIdentify()` | `MessagingPush` (clear token), `MessagingInApp` (reset state), `LocationModule` (clear coordinates), `LiveActivities` (cancel tasks) |

---

## Legacy Migration

On first launch after upgrade from the previous SDK:

1. **Identity** (best-effort): Read `identifiedProfileId` from legacy `UserDefaults`; write to `identity` table.
2. **Anonymous ID** (best-effort): Read from legacy `CioAnalytics` storage; write to `identity` table. Generate fresh UUID if not found.
3. **Push token** (best-effort): Read from legacy `GlobalDataStore` (UserDefaults); write to `device` table.
4. **Event queue**: **Not migrated.** In-flight queued events from the old SDK are abandoned.
5. **Migration flag**: `sdk_meta.legacy_migration_complete = true` set after a successful pass.
