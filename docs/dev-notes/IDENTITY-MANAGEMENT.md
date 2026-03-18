# Identity Management

## Identity Storage

Identity state lives in two layers:

1. **`CioAnalytics` (Segment-based analytics engine)** — the source of truth at runtime. It persists `userId` (named profile) and `anonymousId` (auto-generated UUID, always present) to disk via its own `Storage` system.
2. **`ProfileStore` / `CioProfileStore`** — a legacy key-value store (`SandboxedSiteIdKeyValueStorage`) used only during migration from the old Journeys SDK, keyed by `siteId`. It is read once at startup and then cleared.

---

## Key Lifecycle Events

Events are dispatched over `EventBus` (see `Sources/Common/Communication/Event.swift`) and consumed by subscriber modules. The full registry:

| Event | When it fires | Payload |
|---|---|---|
| `AnonymousProfileIdentifiedEvent` | SDK init — no named user exists | `anonymousId` |
| `ProfileIdentifiedEvent` | `identify()` called, or SDK init with existing `userId`, or migration | `userId` |
| `ScreenViewedEvent` | `screen()` called | screen name |
| `ResetEvent` | `clearIdentify()` → `analytics.reset()` | — |
| `RegisterDeviceTokenEvent` | APN/FCM token registered | token |
| `DeleteDeviceTokenEvent` | token removed | token |
| `TrackMetricEvent` / `TrackInAppMetricEvent` | push/in-app delivery metrics | delivery metadata |

---

## Identity Lifecycle — Step by Step

### 1. SDK Initialization (`DataPipelineImplementation.initialize`)

`postProfileAlreadyIdentified()` is called, which fires:

- **Migration path**: if `migrationSiteId` is set and `ProfileStore` has a saved `profileId` → fires `ProfileIdentifiedEvent`
- **Returning user**: `analytics.userId` is non-nil → fires `ProfileIdentifiedEvent`
- **Anonymous user**: no userId → fires `AnonymousProfileIdentifiedEvent` with `anonymousId`

### 2. `identify(userId:traits:)`

Flows through `DataPipeline` → `DataPipelineImplementation.commonIdentifyProfile()`:

1. Validates userId is non-empty
2. Computes `isChangingIdentifiedProfile` and `isFirstTimeIdentifying`
3. If switching profiles **and** a device token is registered: sends `"Device Deleted"` track event to disassociate the token from the old profile
4. Calls `analytics.identify(userId:traits:)`, which persists the userId
5. **`DataPipelinePublishedEvents` plugin** intercepts the `IdentifyEvent` and posts `ProfileIdentifiedEvent`
6. **`IdentifyContextPlugin` plugin** (`.enrichment` phase) queries all `ProfileEnrichmentProvider`s (e.g. `LocationProfileEnrichmentProvider`) and merges their attributes into the event context
7. If first-time or changing profile **and** a device token exists: re-registers the token to the new profile via `addDeviceAttributes(token:)`

### 3. `identify(traits:)` only (no userId)

Calls `analytics.identify(traits:)` directly — no `ProfileIdentifiedEvent` is fired from `commonIdentifyProfile`; it goes through the analytics plugin pipeline and `DataPipelinePublishedEvents` fires `ProfileIdentifiedEvent` with the `anonymousId`.

### 4. `clearIdentify()`

Flows through `commonClearIdentify()`:

1. Sends `"Device Deleted"` track event (disassociates push token from the profile)
2. Calls `analytics.reset()` — clears userId, traits, generates a new anonymousId
3. **`DataPipelinePublishedEvents.reset()`** fires `ResetEvent`
4. **`IdentifyContextPlugin.reset()`** synchronously calls `resetContext()` on all enrichment providers (clears stale location cache, etc.)

---

## Module Reactions to Identity Events

| Module | `ProfileIdentifiedEvent` | `AnonymousProfileIdentifiedEvent` | `ResetEvent` |
|---|---|---|---|
| **MessagingInApp** | `gist.setUserToken(identifier)` | `gist.setAnonymousId(identifier)` | `gist.resetState()` |
| **Location** | `coordinator.syncCachedLocationIfNeeded()` (re-syncs last known location to new profile) | — | — |
| **Push (APN/FCM)** | auto-registers device token to new profile (handled in `commonIdentifyProfile`) | — | device token deleted |

---

## Profile Enrichment

`ProfileEnrichmentRegistry` is a shared singleton. Modules (e.g., Location) register `ProfileEnrichmentProvider` implementations at init time. On every `identify()` call, `IdentifyContextPlugin` collects attributes from all registered providers and injects them into the event's `context` field before it is serialized and sent. On `reset()`, providers' caches are synchronously cleared via `resetContext()`.
