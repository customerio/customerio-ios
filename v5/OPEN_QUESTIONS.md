# CustomerIO iOS SDK Reimplementation — Open Questions

Design questions that need a decision before or during implementation. Each item
includes the relevant context and tradeoffs gathered so far.

---

## 1. Should Geofencing be a separate module from Location?

**Status:** Resolved — split implemented.

### Background

Geofencing is currently configured as a sub-capability of `LocationConfig` (via
a nested `GeofenceConfig`), and `GeofenceCoordinator` is owned and started by
`LocationModule`. The original rationale was that geofencing requires a device
location to select which regions to hand to `CLLocationManager`.

A closer look reveals this coupling is not actually necessary:

- `GeofenceCoordinator` already owns its own `CLLocationManager` instance
  (separate from the one in `CoreLocationProvider`) used purely for region
  monitoring.
- Adding `startMonitoringSignificantLocationChanges()` to that same manager
  makes the coordinator fully self-contained for candidate selection — coarse
  ~500 m fixes are sufficient to decide which 20 geofences to activate.
- `LocationMode` governs what CIO *reports to the server*; candidate selection
  is purely internal and never reported.
- When the Location module is also active, CoreLocation deduplicates the radio
  work at the OS level, so there is no power cost to having both.

### Necessary changes if separated

| What | Where | Nature |
|---|---|---|
| Move `QuadKey.swift` to `CustomerIO_Utilities` | Currently in Location target | Both modules need it without a cross-module import |
| Move `Geofence.swift`, `GeofenceCoordinator.swift`, `GeofenceLoader.swift`, `GeofenceSyncClient.swift`, `GeofenceStorageMigration.swift`, `Config/GeofenceConfig.swift`, bundle seed JSON | New `Sources/Geofencing/` target | Purely mechanical |
| Create `GeofencingModule.swift` | New file in Geofencing target | Conforms to `CIOModule` + `MigrationProviding`; starts `GeofenceCoordinator`; mirrors shape of `LocationModule` |
| Add `startMonitoringSignificantLocationChanges()` to `GeofenceCoordinator`'s CLLocationManager | `GeofenceCoordinator.swift` | Single logic change — self-supplies location for candidate selection |
| Remove `geofenceCoordinator` property and `updateCandidates()` call | `LocationCoordinator.swift` | Deletion only |
| Remove `geofenceCoordinator` ownership, startup block, and two public monitoring methods from `LocationModule` | `LocationModule.swift` | Deletion only |
| Remove `geofencing: GeofenceConfig` property from `LocationConfig` | `Config/LocationConfig.swift` | One property + init adjustment |
| Move geofence monitoring API off `CustomerIO+Location.swift` | New `CustomerIO+Geofencing.swift` in Geofencing target | `startGeofenceMonitoring()` / `stopGeofenceMonitoring()` hang off the Geofencing module accessor |
| Update `Package.swift` | Root | Add `CustomerIO_Geofencing` product + target |
| Add `SdkConfigBuilder+Geofencing.swift` | Geofencing target | Top-level `.geofencing { GeofenceConfigBuilder()… }` instead of nested under `.location { }` |

### Noteworthy implication

With separation, an app can register Geofencing *without* registering Location.
This is actually correct and desirable — an app that only wants geofence
enter/exit events, with no CIO location tracking, can do exactly that. Under the
current design it is forced to configure a `LocationConfig` purely to reach the
`GeofenceConfig` inside it, which is confusing API surface.

### Decision needed

- Keep as single module (accept the coupling, keep the nested config surface)?
- Split into two independent modules (more work, cleaner API, better composability)?

---

## 2. CEL interpreter selection for aggregation rule predicates

**Status:** Deferred — not needed for v1.

### Background

The `predicate` field is reserved in the rule schema but not evaluated in v1. All three
immediate use cases driving the aggregation engine (screen view volume reduction, noise
suppression, lifecycle event aggregation) require only `eventType` matching, which the
rule's top-level `eventType` field already provides. No per-property filtering is needed
for any of these.

Predicate evaluation becomes relevant when a use case requires filtering on event
*property values* — for example, counting purchases only where `currency == 'USD'`. No
such requirement exists today.

### Options (for future reference)

- **Option A** — Write a scoped CEL subset interpreter in Swift (lexer + parser +
  tree-walking evaluator). No open-source Swift CEL library exists; this is from-scratch
  work. Eliminates any server dependency but is the most implementation effort.
- **Option B** — Server compiles CEL predicates to a versioned expression-tree JSON
  format; SDK walks the tree. Eliminates the parser but still requires a full evaluator,
  adds a versioned wire format, and requires server-side `cel-go` infrastructure.
- **Option C** — Hand-rolled conjunction DSL (simple field comparisons only). Smallest
  client implementation; may not cover all future needs.

### Decision needed (when a concrete use case arises)

Re-evaluate when a rule requirement cannot be expressed as `eventType` match alone.

---

## 3. MessagingInApp — unencrypted UserDefaults storage

**Status:** Open — no action required for v1; revisit if compliance requirements change.

### Background

All `MessagingInApp` persistence goes through `UserDefaultsInAppKeyValueStorage` (backed by
`UserDefaults`). This matches the old SDK's approach and is consistent with industry convention
for in-app messaging state. The `StorageManager` (SqlCipher-encrypted) was not used because
the data is short-lived, re-fetchable from the server, and not user-owned in the same sense
as event queue or identity data.

The five UserDefaults keys in use:

| Key | Contents | Sensitivity |
|---|---|---|
| `broadcastMessages` | JSON-serialized anonymous in-app message payloads cached from the server | Moderate — server-controlled content, not user PII |
| `broadcastMessagesExpiry` | Double timestamp (ms since epoch) marking when the above cache expires | None |
| `broadcastMessagesTracking` | JSON — per-message view counts, dismiss counts, and next-show timestamps | Low — behavioural state, no PII |
| `inboxMessagesOpenedStatus` | JSON `[queueId: Bool]` — which inbox messages the user has opened | Low-moderate — behavioural state |
| `inAppUserQueueFetchCachedResponse` | Raw binary HTTP response body from the queue API (used for 304 Not Modified handling) | Moderate — contains full server message payloads |

### Why this may need revisiting

`inAppUserQueueFetchCachedResponse` holds raw API response bodies in unencrypted
UserDefaults. If a customer embeds user-identifying data in their in-app message custom
properties (e.g. `{"name": "Alice", "account_id": "12345"}`), that data sits unencrypted
in the app sandbox. On a non-jailbroken device, sandbox isolation provides adequate
protection; on a jailbroken device or via iTunes backup, it is readable without the
SqlCipher key.

The remaining four keys hold purely behavioural state (cache timestamps, view counts,
open flags) with no inherent PII risk.

### Decision needed (if compliance requirements arise)

Migrate `inAppUserQueueFetchCachedResponse` (and optionally `broadcastMessages`) into
`StorageManager` if a customer compliance requirement mandates encryption of all cached
server-originated content. The `InAppKeyValueStorage` abstraction already exists as a
seam — the implementation could be swapped for a `StorageManager`-backed one without
changing call sites.

---

## 6. APNs token delivery race condition in `MessagingPushModule`

**Status:** Open — pre-existing issue, not blocking.

### Background

`MessagingPushModule.didRegisterForRemoteNotificationsWithDeviceToken(_:)` is `nonisolated` and can be called by iOS at any point after `UIApplication.shared.registerForRemoteNotifications()` is invoked. The module currently calls `registerForRemoteNotifications()` from within `configure()` (via `autoFetchDeviceToken`), which means the APNs callback *should* arrive well after configure completes — it requires a network round trip to APNs servers.

However, there is no enforcement of this ordering. If the callback fires before `configure()` completes (e.g. a cached token returned synchronously, a very fast APNs response, or a host app calling `registerForRemoteNotifications()` early in its own startup code before `startConfigure()` is called):

- `_onTokenReceived` is `nil` → the token is not persisted to storage
- `_enqueueEvent` is `nil` → the `"Device Created or Updated"` event is silently dropped
- The in-memory `_currentToken` mirror is updated, but `configure()` loads the *stored* token on startup, not the in-memory value — so if the stored token is stale and the new one was never persisted, the backend sees the old token

### Why it has not caused problems

In practice, APNs token delivery always arrives asynchronously after a network round trip. The window between `registerForRemoteNotifications()` and configure completing is measured in milliseconds. No field reports of dropped device registrations attributable to this race have been observed.

### Decision needed

- Accept the current behavior as a known-acceptable race (document and move on)?
- Harden `applyToken()` to buffer the incoming token if `_onTokenReceived` is nil and drain it once configure sets the handler?
- Detect host-app early registration (app calls `registerForRemoteNotifications()` before SDK configure) and emit a warning?

Note: this race exists independently of `installationId` and predates the Live Activity work. It is documented here because the `installationId` timing analysis surfaced it explicitly.

---

## 5. `installationId` — scope, generation, and event inclusion

**Status:** Partially decided — open details remain.

### What has been decided

- The SDK will generate a dedicated `installationId` UUID on first launch, persisted for the lifetime of the app install.
- This is a **new value distinct from `anonymousId`** — not an alias. `anonymousId` continues to serve its existing session/profile identity role.
- `installationId` is exposed as a **read-only property on the root `cio` object**.
- Push notification registration (`"Device Created or Updated"`) will include `installationId` in its payload.
- All Live Activity token registration calls (`PUT /v1/live_activity_push_to_start/…` and `PUT /v1/live_activities/…/push_token`) will include `installationId`.
- The backend will use `installationId` to join regular push token records with Live Activity token records, enabling the silent push start path.

### What is still open

**1. Does `installationId` appear on general tracking events?**

`anonymousId` is stamped on every event by `EventEnricher`. If `installationId` follows the same pattern, partners will see it on all events in their workspace — making it easy to correlate device-level data without any additional steps. If it only appears on device registration events, partners must join via a device registration event to get the value.

Tradeoff: stamping it on all events adds payload overhead and exposes the value more broadly; limiting it to device events is more conservative but less useful for partner-side correlation.

**2. Storage location**

`anonymousId` lives in the `identity` table in `StorageManager`. A dedicated `installationId` could live there too, or in a separate `device` table alongside the push token. The `device` table is a more natural home semantically but requires a storage migration to add the column.

**3. Backend consumption**

Confirm with backend that `installationId` in the push registration payload is sufficient for the cross-record join, or whether it also needs to appear on track events for their use cases.

**4. Transport differentiation for push registration**

A related open question: the backend currently infers push transport (APNs vs FCM) from token format. The reimplemented SDK could make this explicit by adding a `tokenTransport` property to `PushTokenProvider` and including it in the device registration payload. Low urgency — the implicit approach works today — but worth coordinating with the backend team when the Live Activity integration work begins.

---

## 7. Live Activity token re-registration on identity change

**Status:** Open — deferred until identity lifecycle design is revisited.

### Background

When `identify()` is called, `LiveActivitiesModule` updates its in-memory
`_currentUserId` immediately. However, push-to-start tokens and instance push
tokens already registered with the server carry the **previous** identity
(either an anonymous ID or a prior profile ID). The server's partner surface
queries by `(userId, activityType)`, so tokens registered under the old identity
are unreachable under the new one until they naturally rotate.

This affects two token types:

- **Push-to-start tokens** — registered per activity type. The module caches
  the last-registered token hex in storage; the next registration only fires
  when ActivityKit vends a new token, which is outside SDK control.
- **Instance push tokens** — registered per running activity. ActivityKit
  controls token rotation; the SDK re-registers on each rotation event.

### Options

**Option A — Proactive re-registration on identity change.** On `ProfileIdentifiedEvent`,
read all cached push-to-start tokens from storage and re-call the registration
endpoint with the new userId. For running instances, iterate `Activity<T>.activities`
for each registered type and re-send instance token registrations. Requires the
re-registration logic to be captured in each `ActivityTypeRegistration` alongside
the existing observation closures (the concrete `T` must be in scope).

**Option B — Force rotation by clearing the cache.** On identity change, clear
the stored push-to-start token hex for each activity type. The next time ActivityKit
re-emits the token (which it does periodically), the changed-token check passes
and the endpoint is called with the new userId. Does not work for instance tokens
(no cache to clear — ActivityKit controls emission).

**Option C — Accept the gap.** Tokens registered under the previous identity
remain valid for the lifetime of that token. The server could resolve by
`installationId` join if the backend is extended to support it. Simplest
implementation; acceptable if identity switches are rare and token rotation
is frequent enough to close the gap naturally.

### Decision needed

- Which option best matches the expected identity lifecycle for Live Activity users?
- Does the partner surface need to guarantee zero-gap coverage across identity
  switches, or is eventual consistency (via token rotation) acceptable?

---

## 8. Live Activity `transport` field — SDK configuration and server necessity

**Status:** Open — decision needed before the server API is finalised.

### Background

The `transport` field (`"apns"` or `"fcm"`) is included in Live Activity token
registration payloads (`PUT /v1/live_activities/registration/{activityType}` and
`PUT /v1/live_activities/{activityId}/push_token`) to signal to the server which
delivery infrastructure to use when pushing to the device.

The current SDK implementation hardcodes `transport = "apns"` in
`LiveActivityClient.swift`. There is no mechanism for the host app or the push
module to communicate the partner's actual transport configuration to the Live
Activities module.

### The problem

If the `transport` field is kept in the server spec, the SDK needs a way to
determine the correct value at runtime:

- Partners using direct APNs → `"apns"`
- Partners routing iOS push through Firebase → `"fcm"`

The natural source of this value is the push module's provider configuration
(`APNPushProvider` vs a Firebase-backed provider). The Live Activities module
currently has no dependency on the push module and no access to its configuration.

### Options

**Option A — Remove `transport` from the server spec.** The server already knows
the partner's push configuration from their account settings. It can infer the
correct delivery path without the SDK declaring it on every request. Simplest
outcome for the SDK — the field is dropped entirely.

**Option B — Derive from push module configuration.** Introduce a protocol or
shared config value that lets the push module advertise its transport to other
modules. `LiveActivitiesModule` reads this at configure time and includes the
correct value in registration payloads.

**Option C — Expose as explicit Live Activity config.** Add a `transport` field
to `LiveActivityConfig` / `LiveActivityConfigBuilder` and let the host app set it
directly. Simple to implement but creates a new integration requirement and a
potential source of misconfiguration.

### Decision needed

- Should `transport` be removed from the Live Activity registration endpoints
  entirely, with the server deriving delivery path from account configuration?
- If retained, which option best fits the SDK's module boundary design?

---

## 4. Live Activity template library — dynamic asset loading

**Status:** Open — design needed before implementation.

### Background

Live Activity `ContentState` payloads delivered via APNs are capped at 4KB, ruling out
inline image data. `AsyncImage` is not reliable in widget extension rendering contexts
because views are captured as snapshots rather than rendered as live SwiftUI views.
The practical path for dynamic images in Live Activity templates is an App Group shared
container: the SDK pre-downloads assets and the widget reads them from disk by key.

This arose during evaluation of a Live Activity template library where each template
would be a `(ActivityAttributes, Widget, BannerView)` triple distributed as a Swift
Package, with the server declaring which template and assets to use.

### What needs to be designed

**Asset manifest contract** — The server needs to declare the full set of image URLs a
template may reference before any activity using that template starts. This fits the
existing pattern of server-driven configuration but requires a new manifest schema.

**SDK cache layer** — The SDK must:
- Receive the asset manifest (likely alongside the template definition at configure time
  or via a background fetch)
- Download and store assets in an App Group container accessible to the widget extension
- Manage cache eviction and staleness (size limits, TTL, template retirement)
- Guarantee assets are warm before `Activity.request(...)` is called and before a
  content-state push arrives

**Fallback behavior** — If a push arrives for a template whose assets are not yet cached
(fresh install, cache evicted, background fetch not yet run), the template needs a defined
fallback: placeholder asset, text-only degraded layout, or delayed render. This must be
specified before implementation, not discovered during it.

**App Group provisioning** — Host apps must configure a shared App Group entitlement that
both the main app and the widget extension belong to. This is an integration requirement
that needs to be surfaced clearly in the SDK setup guide.

### Decision needed

- What does the asset manifest schema look like, and where in the server-side platform
  does it live?
- What is the eviction policy (size cap, TTL, keyed by template version)?
- What is the required fallback when an asset is missing at render time?
- Is asset pre-warming a responsibility of the SDK or the host app?
