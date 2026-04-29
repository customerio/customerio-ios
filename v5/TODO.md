# CustomerIO iOS SDK Reimplementation — Outstanding Work

Items are ordered by dependency: each item can only be started once the items
above it (that it depends on) are complete.

---

## 1. EventBus domain event types

**Files to create/edit:** `Sources/CustomerIO/Events/` (new), `CustomerIO.swift`, `IdentityStore`

Define the SDK-level events that modules subscribe to. These are a hard
prerequisite for the MessagingInApp EventBus subscriptions (item 5).

- [x] Define `ProfileIdentifiedEvent` (identifier: String)
- [x] Define `AnonymousProfileIdentifiedEvent` (identifier: String)
- [x] Define `ScreenViewedEvent` (name: String)
- [x] Define `ResetEvent`
- [x] Post `ProfileIdentifiedEvent` / `AnonymousProfileIdentifiedEvent` from `CustomerIO.identify()`
- [x] Post `ResetEvent` from `CustomerIO.clearIdentify()`
- [x] Post `ScreenViewedEvent` from `CustomerIO.screen()`
- [x] Pass `CommonEventBus` through `configure()` and into modules that need it

---

## 2. `MessagingPush` — unified module

**Files:** `Sources/MessagingPush/` (interface stubs exist; implementation pending)

The two former stub targets (`MessagingPushAPN`, `MessagingPushFCM`) are
replaced by a single `CustomerIO_MessagingPush` target. Token delivery is
selected at config time via `PushTokenProvider`. See `MESSAGINGPUSH.md`.

- [x] Define `PushTokenProvider` protocol + `APNPushProvider`
- [x] Define `PushConfig` struct
- [x] Define `PushConfigBuilder` (main app only; NSE config moved to `CustomerIO_MessagingPushNSE`)
- [x] `SdkConfigBuilder.push { }` extension
- [x] `MessagingPushModule` actor stub + `cio.push` accessor
- [x] `CIONotificationServiceExtension` base class in `CustomerIO_MessagingPushNSE` (standalone, Foundation-only; replaces `MessagingPushExtension`)
- [x] `CIOModule.preActivate(_:)` — default no-op on protocol extension
- [x] `CustomerIO.activateModulesForLaunch(_:)` — synchronous pre-launch activation
- [x] `startConfigure` calls `activateModulesForLaunch` before Task; `onCompletion: (Error?) -> Void` always called
- [x] Update `Package.swift`: add `CustomerIO_MessagingPush` and `CustomerIO_MessagingPushNSE` targets and products; remove legacy `CustomerIO_MessagingPushAPN` and `CustomerIO_MessagingPushFCM` stubs
- [x] `MessagingPushModule.preActivate(_:)`: if `autoTrackPushEvents`, create `PushNotificationCenterRegistrar` and call `activate()` (registers as `UNUserNotificationCenter` delegate in buffering mode)
- [x] `MessagingPushModule.configure()`: App Group detection → `sdk_meta` + device attribute
- [x] `MessagingPushModule.configure()`: wire `provider.observeTokenRefresh` → token storage (via `StorageManager+Push`; token mirrored in `_currentToken: Synchronized<String?>` on the module)
- [x] `MessagingPushModule.configure()`: subscribe to `ResetEvent` → clear push token and wipe `io.customer.sdk/push-delivery/` directory
- [x] `MessagingPushModule.configure()`: drain App Group delivery queue on startup — delete `*.tmp` stragglers, then decode/enqueue/delete each `*.json` record one at a time
- [x] `MessagingPushModule.configure()`: at completion call `registrar.setReady(listener:)` to drain pre-configure buffer
- [x] `didRegisterForRemoteNotifications`: call provider, persist token via `_onTokenReceived`, upload device-update event
- [x] `didFailToRegisterForRemoteNotifications`: log via SDK logger
- [x] Implement payload types: `PushNotification`, `CustomerIOParsedPushPayload`, `PushNotificationAction`, `UNNotificationWrapper`, `UNResponseWrapper`
- [x] Implement `PushEventHandler` + `PushEventHandlerProxy`
- [x] Implement `PushNotificationCenterRegistrar` (buffering mode + `setReady(listener:)` drain)
- [x] Implement `IOSPushEventListener` — Live Activity guard on both paths; dedup via `PushHistory`; CIO-vs-non-CIO branching; `PushClickHandler` for tracking/deep-link; proxy forwarding
- [x] Implement `PushClickHandler` (metric tracking, deep link routing via `DeepLinkUtil`, attachment cleanup)
- [x] Implement `PushHistory` (in-memory deduplication by push ID + delivery date)
- [x] Implement manual push handling overloads (`userNotificationCenter(didReceive:...)`, `userNotificationCenter(willPresent:...)`)
- [x] `CIONotificationServiceExtension`: App Group delivery queue — write `delivery-<UUID>.tmp`; rename to `delivery-<UUID>.json`
- [x] `CIONotificationServiceExtension`: direct HTTP upload to `/v1/track` for real-time delivery;
      App Group written eagerly as fallback, deleted on upload success. Concurrent with image download.
- [x] `CIONotificationServiceExtension`: rich push image download with cached `URLSession`
- [x] `CIONotificationServiceExtension`: `serviceExtensionTimeWillExpire()` cancel + flush

---

## 3. Device registration — attributes, token lifecycle, and profile switching

**Files:** `Sources/CustomerIO/CustomerIO.swift`, `Sources/CustomerIO/Store/DeviceStore.swift`,
`Sources/CustomerIO/Pipeline/EventEnricher.swift`

The old SDK emits a `"Device Created or Updated"` track event whenever a push
token is first registered or device attributes change, and a `"Device Deleted"`
track event whenever the active profile switches so the old profile stops
receiving push. Neither behaviour exists yet.

### 3a. Auto-collected device attributes

The `autoTrackDeviceAttributes` config option controls whether the SDK
automatically collects OS facts and attaches them to the device-registration
event. When enabled, the following properties are assembled and sent as the
body of `"Device Created or Updated"`:

| Property | Source |
|---|---|
| `cio_sdk_version` | `CustomerIO.sdkVersion` |
| `app_version` | `Bundle.main` `CFBundleShortVersionString` |
| `device_locale` | `Locale.preferredLanguages.first`, formatted as `"en-US"` |
| `device_manufacturer` | hardcoded `"Apple"` |
| `device_model` | `UIDevice.deviceModelCode` (UIKit) |
| `device_os` | `UIDevice.current.systemVersion` |
| `push_enabled` | async query of `UNUserNotificationCenter.getNotificationSettings` |
| `network_bluetooth` | Segment context `network.bluetooth` |
| `network_cellular` | Segment context `network.cellular` |
| `network_wifi` | Segment context `network.wifi` |
| `screen_width` / `screen_height` | Segment context `screen` |
| `timezone` | Segment context `timezone` |
| `ip` | Segment context `ip` |

- [x] Add `autoTrackDeviceAttributes: Bool` to `SdkConfig` and `SdkConfigBuilder`
      (default `true`, matching old SDK behaviour)
- [x] Create `DeviceInfoProvider` in `Sources/MessagingPush/DeviceInfo/DeviceInfoProvider.swift`
      to encapsulate OS fact collection; UIKit imports behind `#if canImport(UIKit)`.
      Uses `UIDevice.modelCode` extension (sysctlbyname hw.machine) for hardware ID.
      `network_bluetooth`, `network_cellular`, `network_wifi`, `ip` deferred — require
      system entitlements beyond scope of this item.
- [x] Persist custom attributes from `setDeviceAttributes(_:)` in-memory on `CustomerIO`
      via `_customDeviceAttributes: Synchronized<[String: Variant]>` (package access);
      `DeviceStore` not extended — custom attributes are ephemeral and assembled fresh
      per event. `setDeviceAttributes` also posts `DeviceAttributesChangedEvent`.
- [x] When a push token is registered, assemble the full attribute payload
      (auto-collected + custom) and enqueue a `"Device Created or Updated"` event
      via `emitDeviceCreatedOrUpdated()` called from `applyToken(_:)`
- [x] When `setDeviceAttributes` is called while a token is already registered,
      re-emit `"Device Created or Updated"` (push module subscribes to `DeviceAttributesChangedEvent`)
- [x] When `autoTrackDeviceAttributes` is `false`, send only custom attributes
      (guard on `_autoTrackDeviceAttributes` in `emitDeviceCreatedOrUpdated()`)

### 3b. Device token deletion on profile switch

The old SDK detects when `identify()` is called for a *different* user than the
currently identified one. It then:
1. Emits `"Device Deleted"` to disassociate the device from the old profile.
2. Calls `addDeviceAttributes` (re-registration) to associate the device with
   the new profile.

This prevents the old profile continuing to receive push notifications after
a sign-out / sign-in cycle.

- [x] `MessagingPushModule` subscribes to `ProfileIdentifiedEvent`; tracks last known
      profile ID in `_lastProfileId: Synchronized<String?>`. On profile switch with
      a registered token: enqueues `"Device Deleted"` synchronously then starts a Task
      to call `emitDeviceCreatedOrUpdated()`. Implementation note: "Device Deleted"
      arrives in the upload queue AFTER the Identify event (both come from the same
      `identify()` call; spec says "before" but the async event bus makes strict
      ordering impractical without major architecture changes — recorded in ADR below).
- [x] After profile switch, `emitDeviceCreatedOrUpdated()` registers the token
      against the new profile
- [x] On `clearIdentify()` (i.e. `ResetEvent`), if a push token is registered,
      emit `"Device Deleted"` before clearing the token (implemented in ResetEvent handler;
      also fixed pre-existing bug where the ResetEvent observer token was not retained —
      now stored in `_observerTokens: [AnyObject]`)

---

## 4. `MessagingInApp` — engine + EventBus wiring

**File:** `Sources/MessagingInApp/MessagingInAppModule.swift`

Depends on: **item 1** (EventBus event types), **item 2** (push module, for delivery tracking patterns)

- [x] `configure()`: initialise in-app message display engine (Gist/new engine)
- [x] Subscribe to `ProfileIdentifiedEvent` → call engine's `setUserToken(_:)`
- [x] Subscribe to `AnonymousProfileIdentifiedEvent` → call engine's `setAnonymousId(_:)`
- [x] Subscribe to `ScreenViewedEvent` → forward to engine for trigger matching
- [x] Subscribe to `ResetEvent` → call engine's `resetState()`

**Additional work completed (Phase 3 + Phase 4 Swift 6 migration):**
- [x] `GistDelegate` protocol extracted; `NoOpGistDelegate` added for non-UIKit platforms
- [x] `SseLifecycleManager` protocol + `CioSseLifecycleManager` (UIKit) + `NoOpSseLifecycleManager` (non-UIKit)
- [x] `Gist` actor stores `any GistDelegate` (not concrete `GistDelegateImpl`) for cross-platform compilation
- [x] `MessagingInAppModule` uses `Synchronized<Gist?>` + `Synchronized<(any NotificationInbox)?>` for nonisolated public API
- [x] Observer tokens retained in `observerTokens: [AnyObject]` to prevent immediate deregistration
- [x] `trackMetric` closure injected into `GistDelegateImpl` and `DefaultNotificationInbox`; fires `"Report Delivery Event"` track
- [x] `DefaultNotificationInbox` implemented (`@MainActor`, `@unchecked Sendable`, topic filtering, `AsyncStream` API)
- [x] `NoOpNotificationInbox` implemented for unconfigured module
- [x] `SdkConfigBuilder.inApp { }` extension implemented

---

## 7. `Location` — start location services

**File:** `Sources/Location/LocationModule.swift` (L17)

No hard dependencies on earlier items.

- [x] `configure()`: read `config.location`; start `LocationServices` / `CoreLocationProvider` based on config

---

## 8. `AggregationEngine` — accumulator state + remote config

**File:** `Sources/CustomerIO/Aggregation/AggregationEngine.swift`

No hard dependencies on earlier items, but should land after the core pipeline
is stable.

- [x] Count accumulator: increment count in `aggregation_state` table on each matching event
- [x] Numeric accumulator: update min/max/sum/count/min/max/assign/assignIfNull/countUnique/histogram in `aggregation_state` on each matching event
- [x] Remote config fetch: rate-limited GET (24-hour guard via `AggregationConfig.fetchedAt`)
- [x] Remote config fetch: persist new rules to storage via `setAggregationConfig`
- [x] Remote config fetch: swap config atomically, preserving accumulator state by ruleId, flushing removed rules
- [x] `loadCachedRuleset()`: restore from storage on startup, fall back to bundled `default-aggregation-rules.json`
- [x] `flushIfDue()`: iterate accumulators, synthesise + enqueue derived event for each overdue rule
- [x] `handleReset()`: clear profile-scoped accumulator state on `ResetEvent`
- [x] `refreshConfigIfNeeded()` and `flushIfDue()` called once at startup from `CustomerIO.configure()`
- [x] `flushIfDue()` called on foreground (`willEnterForegroundNotification`) alongside `scheduler.flush()`; intentionally omitted from background to avoid upload cancellation on suspend
- [x] Test coverage added — all 8 behavioral scenarios (32–39) covered across `AggregationEngineAccumulationTests`, `AggregationEnginePersistenceTests`, and additions to existing suites

---

## 9. Live Activities / Live Updates

Full design in `LIVEACTIVITIES.md`. Wire format uses dedicated REST endpoints for token
registration (not the event queue); analytics events go through the standard track pipeline.

**Prerequisites (must be resolved before implementation starts):**

- [ ] Confirm endpoint paths and auth scheme with backend team
- [ ] Confirm whether `apns-push-type: liveactivity` reuses the existing `.p8` key or requires a separate one
- [ ] Confirm Android 16 API level and any required manifest declarations
- [ ] Confirm backend readiness to handle `apns-push-type: liveactivity` push type

### 9a. iOS — `LiveActivitiesModule`

**Files:** `Sources/LiveActivities/` (new target); `#if os(iOS)` throughout

Depends on: **item 1** (EventBus — `ResetEvent`).

- [ ] Define `CIOActivityAttributes` protocol (`cioActivityType`, `cioActivityId`, `cioMetadata`)
- [ ] Define `ActivityEndReason` enum (`unknown`, `userDismissed`, `expired`, `programmatic`)
- [ ] Define `LiveActivityConfigBuilder` with `.register<T: CIOActivityAttributes>(_:)` storing type-erased `ActivityTypeRegistration` closures
- [ ] Add `SdkConfigBuilder+LiveActivities.swift` (`.liveActivities { LiveActivityConfigBuilder() }`)
- [ ] Add `CustomerIO+LiveActivities.swift` (`cio.liveActivities` accessor)
- [ ] Add `LiveActivityStorageMigration` — `live_activity_state` + `live_activity_push_to_start_state` tables (migration id `005-live-activity-schema`)
- [ ] Add `StorageManager+LiveActivities.swift` extension
- [ ] Implement `LiveActivitiesModule` actor
- [ ] Implement `nonisolated resumeTracking()` — iterate registered type boxes, call `trackActivity` for each existing activity, begin push-to-start observation
- [ ] Implement `trackActivity<T: CIOActivityAttributes>(_ activity: Activity<T>)` — extract protocol fields, call token observation, auto-observe `activityStateUpdates`
- [ ] Implement `trackActivity(tokenUpdates:activityId:activityType:attributes:)` — explicit overload, per-activity token observation task
- [ ] Implement token observation task: first token → PUT + "Started" event; rotation → PUT only; stream end → auto-end
- [ ] Implement `activityDidEnd(activityId:reason:)` — DELETE endpoint + "Ended" analytics event
- [ ] Implement `nonisolated activityDidReceiveInteraction(activityId:)` — calls `root.track(...)` directly, no Task or await at call site
- [ ] Implement `registerActivityToken(_:activityId:activityType:attributes:)` — single-shot, no observation loop
- [ ] Implement `trackPushToStartToken(updates:activityType:)` (iOS 17.2+) — push-to-start token observation task
- [ ] Subscribe to `ResetEvent` → cancel all tasks, clear both storage tables
- [ ] Ship `asAsyncStream()` convenience extension on `AsyncSequence`
- [ ] Add `LiveActivitiesModule` to `Package.swift`

### 9b. Android — `LiveUpdatesModule`

**Files:** Android library target (TBD); degrades to no-op on pre-Android-16

Depends on: EventBus `ResetEvent` equivalent on Android.

- [ ] Define `LiveUpdateConfig` data class
- [ ] Add SDK config builder extension for `.liveUpdates { LiveUpdateConfig() }`
- [ ] Add `cio.liveUpdates` accessor
- [ ] Implement `trackNotification(notificationId, activityType, attributes)` — "Live Update Shown" event
- [ ] Implement `notificationEnded(notificationId, reason)` — "Live Update Ended" event
- [ ] Implement `notificationInteracted(notificationId, actionId)` — "Live Update Interacted" event
- [ ] Handle incoming FCM messages with `cio_live_update: true` and `cio_action: end` — auto-cancel notification and emit ended event
- [ ] Set device capability attribute `live_updates_supported: true` on Android 16+ devices
- [ ] Degrade gracefully (no-op with debug log) on pre-Android-16 devices

---

## 10. Obj-C bridge — `isConfigured`

**File:** `Sources/CustomerIO/ObjC/CIOBridge.swift`

- [x] `_isConfigured: Synchronized<Bool>` on `CustomerIO`, set at end of `configure()`
- [x] `public nonisolated var isConfigured: Bool` on `CustomerIO`
- [x] `CIOBridge.isConfigured` reads from it via `cio.isConfigured`

---

## 11. Upload scheduler — configurable flush policies

**Files:** `Sources/CustomerIO/SdkConfig.swift`, `Sources/CustomerIO/SdkConfigBuilder.swift`,
`Sources/CustomerIO/Pipeline/UploadScheduler.swift`

The old SDK exposes `flushAt` (number of queued events that triggers an
immediate upload) and `flushInterval` (maximum elapsed time between uploads)
as first-class configuration options. The new `UploadScheduler` exists but
its policies are hard-coded.

- [x] Add `flushAt: Int` to `SdkConfig` and `SdkConfigBuilder` (default `20`)
- [x] Add `flushInterval: TimeInterval` to `SdkConfig` and `SdkConfigBuilder`
      (default `30` seconds)
- [x] Wire `flushAt` into `UploadScheduler.uploadIfNeeded()` — upload
      immediately when the queue depth reaches this threshold
- [x] Wire `flushInterval` into `UploadScheduler` as a one-shot timer: started
      when the first event enters the queue after a flush, cancelled if `flushAt`
      is hit first or a lifecycle flush fires
- [x] Flush on `UIApplication.didEnterBackgroundNotification`; upload on
      `UIApplication.willEnterForegroundNotification`
- [ ] Wrap background flush in `UIApplication.beginBackgroundTask` to extend
      the available window beyond the default (~5s) for slow network conditions

---

## 12. HTTP `User-Agent` header

**File:** `Sources/CustomerIO_Utilities/Networking/HttpRequestRunner.swift`

The old SDK builds a `User-Agent` request header of the form
`"iOS Client/1.0.0"` and sends it on every API call. The backend uses this
to distinguish native iOS installs from cross-platform wrapper SDKs
(React Native, Flutter).

- [x] Add `httpUserAgent: String` to `SdkConfig` (default `"iOS Client/<sdkVersion>"`)
      and `httpUserAgent(_ userAgent: String)` to `SdkConfigBuilder`
- [x] Set `User-Agent` header in `BatchRequestBuilder.buildRequest(...)` from
      `config.httpUserAgent`
- [x] Expose `httpUserAgent` to `DeviceInfoProvider` so `"cio_sdk_version"` in
      device attributes matches the wrapper SDK version when set

---

## 13. Screen view routing mode

**Files:** `Sources/CustomerIO/SdkConfig.swift`, `Sources/CustomerIO/SdkConfigBuilder.swift`,
`Sources/CustomerIO/Pipeline/EventEnricher.swift` (or `EventProcessor.swift`)

The old SDK has a `ScreenView` enum controlling how screen events are handled:

- `.all` — events are sent to the backend **and** used for in-app message page
  rules (current new SDK behaviour).
- `.inApp` — events are kept on device for in-app message trigger matching
  **only**; they are never uploaded to the backend.

This matters for apps that use in-app messaging with page rules but do not
want screen views in their analytics.

- [x] Define `CIOScreenViewMode` enum (`.all`, `.inApp`) in `SdkConfig.swift`
- [x] Add `screenViewMode: CIOScreenViewMode` to `SdkConfig` and
      `SdkConfigBuilder` (default `.all`)
- [x] When `.inApp`, inject a local `discard` rule into `AggregationEngine`
      at configure time via a type-level wildcard key (`"$screen"`). The
      `ScreenViewedEvent` bus post in `CustomerIO.screen()` is unaffected.
      Local rules are re-applied after every `applyRuleset()` call to survive
      server config refreshes without duplication. Deprecate `screenViewMode`
      once server-driven aggregation config can deliver the equivalent rule.

---

## 14. Application lifecycle event tracking

**Files:** `Sources/CustomerIO/SdkConfig.swift`, `Sources/CustomerIO/SdkConfigBuilder.swift`,
`Sources/CustomerIO/CustomerIO.swift` (new `AppLifecycleTracker` type)

The old SDK can automatically emit the following analytics events in response
to UIApplication / UIScene notifications:

| Event name | Trigger |
|---|---|
| `"Application Installed"` | First launch (no previous version in storage) |
| `"Application Updated"` | Launch with a different `CFBundleShortVersionString` than stored |
| `"Application Opened"` | `UIApplication.didBecomeActiveNotification` |
| `"Application Backgrounded"` | `UIApplication.didEnterBackgroundNotification` |

- [x] Add `trackApplicationLifecycleEvents: Bool` to `SdkConfig` and
      `SdkConfigBuilder` (default `true`)
- [x] Create `AppLifecycleTracker` — stores previous app version in
      `StorageManager`; compares on each launch to detect install vs. update
- [x] Wire `AppLifecycleTracker` into `CustomerIO.configure()` behind the flag
- [x] Emit lifecycle events via `enqueueEvent(.trackSynthesized(...))` so they
      pass through the normal pipeline (enrichment, aggregation, upload)
- [x] Emit `"Application Opened"` / `"Application Backgrounded"` by subscribing
      to `UIApplication` notifications from within the tracker
- [x] Emit `"Application Installed"` or `"Application Updated"` once per launch
      (not once per configure call — guard against double-firing)

---

## 15. `SdkConfigBuilder` — custom API host override

**Files:** `Sources/CustomerIO/SdkConfig.swift`, `Sources/CustomerIO/SdkConfigBuilder.swift`,
`Sources/CustomerIO_Utilities/Networking/HttpRequestRunner.swift`

The Flutter (and React Native) wrappers pass through `apiHost` and `cdnHost`
values from the host app's config. When provided, these override the host
derived from `CIORegion`. The new SDK currently only supports region selection
and has no mechanism for a raw host override.

- [x] Add `apiHost: URL?` and `cdnHost: URL?` to `SdkConfig` and `SdkConfigBuilder`
      (both default to `nil`, falling back to `region.baseURL`)
- [x] `BatchRequestBuilder` prefers `config.apiHost` over `region.baseURL` when non-nil
- [x] Wire `cdnHost` into the in-app messaging CDN fetch path. Stored in
      `InAppMessageState.cdnHost: URL?`; exposed via `effectiveRendererBaseURL`
      computed property (returns `cdnHost` when set, otherwise falls back to
      `environment.networkSettings.renderer`). `EngineWeb.loadMessage` uses the
      computed property. Set from `config.cdnHost` in `MessagingInAppModule.configure()`.

---

## 16. Push module — public surface for wrapper SDK integration

**Files:** `Sources/MessagingPush/MessagingPushModule.swift`,
`Sources/CustomerIO/Store/DeviceStore.swift`

Gaps identified via the Flutter wrapper's public API that need resolution
before any wrapper SDK can ship push support.

### 16a. `unregisterDevice()`

✅ Implemented in `MessagingPushModule`. Emits `"Device Deleted"` to the
backend via the core event pipeline, retaining the local token for
automatic re-registration on the next profile change. `nonisolated` —
callable as `cio.push.unregisterDevice()` without `await`.

### 16b. `registerDeviceToken(_ token: String)`

✅ Implemented in `MessagingPushModule`. Public `nonisolated func registerDeviceToken(_ token: String)`
dispatches to `applyToken(_:)`, which persists the token via `StorageManager` and
triggers the same registration flow as the native APNs path. Lives on `cio.push`.

### 16c. `registeredDeviceToken: String?`

✅ Implemented in `MessagingPushModule`. Public `nonisolated var registeredDeviceToken: String?`
reads `_currentToken` via `Synchronized.using { $0 }` — no `await` needed.

---

## Test coverage tracker

Legend: ✅ mostly complete · ⚠️ partial / stub · ❌ none

### `CustomerIO_Utilities`

| Type | Kind | Tests |
|---|---|---|
| `Synchronized<T>` | class | ✅ core ops, arithmetic, bool, collections, comparable, dictionaries, equatable, hashable |
| `DependencyContainer` | class | Removed — init-based injection used throughout; git history if needed |
| `CommonEventBus` / `EventBus` | class / protocol | ✅ post, wrong-type filter, multi-observer, token deregistration |
| `JsonAdapter` | struct | ✅ encode/decode, ISO 8601 dates, errors |
| `QuadKey` | enum | ✅ known cities, zoom boundaries, edge cases |
| `RegistrationToken` | class | ✅ indirectly via `EventBusTests` |
| `SystemDateProvider` / `DateProviding` | struct / protocol | ✅ indirectly via `EventEnricherTests` stub |
| `StorageManager` | struct | ✅ full coverage — all public APIs tested |
| `HttpRequestRunner` / `HttpClient` | class / protocol | ✅ performRequest success/error, URLSession mock |
| `MigrationRunner` / `LegacySeeds` | actor / struct | ✅ legacySeeds, markComplete, isComplete |
| `ApiKeyDatabaseKeyProvider` | struct | ✅ key passthrough, empty key |
| `KeychainDatabaseKeyProvider` / `KeychainError` | struct / enum | ✅ generation, 64-char hex, idempotency, fresh-instance persistence, API-key isolation, service-name isolation, randomness |

### `CustomerIO`

| Type | Kind | Tests |
|---|---|---|
| `CustomerIO` | actor | ✅ configure, isConfigured, idempotency, nonisolated API buffering, EventBus delivery |
| `SdkConfig` / `SdkConfigBuilder` | struct | ✅ all defaults, every fluent method, immutability, module attachment |
| `CIORegion` / `CIOLogLevel` | enum | ✅ baseURL for `.us`/`.eu`; ordering, equality, `>=` guard semantics, raw value ascension |
| `Variant` / `VariantConvertible` + extensions | enum / protocol | ✅ literals, all 9 cases, JSON + PropertyList + NSKeyedArchiver |
| `ModuleRegistry` | class | ✅ register, retrieve, nil for unregistered, overwrite semantics, `allModules` |
| `BatchAssembler` | struct | ✅ empty, count limit, byte limit, order preservation |
| `BatchRequestBuilder` | struct | ✅ URL, method, headers, auth, wire format for all 3 event types |
| `EventEnricher` | actor | ✅ all 6 `PendingEvent` cases, timestamp, anonymousId, `ProfileEnhancing` contributions |
| `EnrichedEvent` / `EventType` | struct / enum | ✅ covered as I/O of `EventEnricher` + `BatchRequestBuilder` |
| `AggregationRule` / `AggregationRuleset` / `AggregateOperation` / `AccumulatorValue` | structs / enum | ✅ all Codable paths, all 9 operations, scope, reset |
| `PendingEvent` | enum | ✅ indirectly as input to `EventEnricher` |
| `CIOEvent` (all 4 nested structs) | enum / structs | ✅ |
| `CIOModule` / `ProfileEnhancing` | protocols | ✅ via stubs in `SdkConfigBuilderTests` + `EventEnricherTests` |
| `AggregationEngine` / `AggregationConfig` / `AggregationResult` | actor / struct / enum | ✅ evaluate routing, accumulation (count/stats), server discard, flush scheduling, reset scoping, config refresh, persistence across restart, ruleset update preservation, removed-rule flush |
| `EventQueue` / `PersistedEvent` | actor / struct | ✅ enqueue/peek/delete roundtrip, count, FIFO order, limit, JSON field preservation |
| `UploadScheduler` | actor | ✅ flush, uploadIfNeeded, FIFO ordering, 5xx retry + recovery |
| `IdentityStore` | actor | ✅ anonymous ID generation + stability + persistence, profile ID set/reset, seeding guards |
| `DeviceStore` | actor | ✅ set/clear/overwrite token, loadFromStorage, seeding guards |
| `CIOBridge` | class | ❌ ObjC bridge |
| `CIOAutoTrack` / `CIOScreenTrackingModifier` | enum / struct | ❌ UIKit/SwiftUI screen tracking, requires host app |

### `CustomerIO_Location`

| Type | Kind | Tests |
|---|---|---|
| `LocationModule` | actor | ❌ requires `CoreLocationProvider` (iOS) |
| `LocationCoordinator` | actor | ❌ `init` requires concrete `CustomerIO` root; no seam without full SDK setup |
| `LocationConfig` / `LocationMode` | struct / enum | ✅ all four modes distinct, defaults, every init param |
| `AppLifecycleObserver` | class | ❌ driven by `UIApplication` notifications; requires live iOS environment |
| `LocationStorageMigration` | struct | ✅ migration runs, idempotent, stable ID; all four location keys round-trip and clear correctly |

### `CustomerIO_Geofencing`

| Type | Kind | Tests |
|---|---|---|
| `GeofencingModule` | actor | ❌ |
| `GeofenceSyncClient` / `GeofenceSyncError` | struct / enum | ❌ |
| `GeofenceLoader` | enum | ❌ |
| `GeofenceConfig` / `GeofenceMode` | struct / enum | ❌ |
| `GeofenceStorageMigration` | struct | ❌ |
| `Geofence` | struct | ❌ |

### `CustomerIO_MessagingPush`

| Type | Kind | Tests |
|---|---|---|
| `MessagingPushModule` | actor | ❌ needs UIKit/UN stubs |
| `PushConfig` / `PushConfigBuilder` | struct | ❌ |
| `PushTokenProvider` / `APNPushProvider` | protocol / struct | ❌ |
| `PushNotification` protocol extensions | protocol | ✅ `PushNotificationTests` |
| `UNNotificationWrapper` / `UNResponseWrapper` | classes | ❌ needs UNNotification |
| `PushEventHandler` / `PushEventHandlerProxy` | protocol / class | ✅ `PushEventHandlerProxyTests` |
| `PushNotificationCenterRegistrar` | class | ❌ needs UNUserNotificationCenter |
| `IOSPushEventListener` | class | ❌ needs UNNotification |
| `PushClickHandler` | struct | ✅ `PushClickHandlerTests` — trackOpened/trackDelivered via `MockCIOTrackingClient` |
| `PushHistory` | class | ✅ `PushHistoryTests` |
| `DeepLinkUtil` | enum | ❌ needs UIKit |
| `DeliveryQueue` | struct | ✅ `DeliveryQueueTests` |
| `DeliveryQueueRecord` | struct | ✅ `DeliveryQueueRecordTests` |
### `CustomerIO_MessagingPushNSE`

| Type | Kind | Tests |
|---|---|---|
| `CIONotificationServiceExtension` | class | ❌ needs NSE context |
| `CIONSERegion` | enum | ❌ |
| `DeliveryQueue` (write side) | struct | ❌ |
| `DeliveryQueueRecord` | struct | ❌ |

### `CustomerIO_MessagingInApp`

| Type | Kind | Tests |
|---|---|---|
| `InAppMessageReducer` | enum | ✅ all action cases, persistent/non-persistent message logic |
| `InAppMessageStore` | actor | ✅ dispatch, subscribe/notify, unsubscribe, multi-subscriber |
| `InboxMessage` | struct | ✅ init, copy, equality, sorting, topic matching |
| `DefaultNotificationInbox` | class | ✅ getMessages, addChangeListener, removeChangeListener, markOpened/deleted/clicked, messages(topic:) AsyncStream |
| `InboxMessageCacheManager` | class | ✅ save/get/clear opened status, clearAll |
| `HeartbeatTimer` | actor | ✅ fires after timeout, reset cancels, generation guard, double-start cancels first |
| `SseRetryHelper` | actor | ✅ immediate first retry, sleeper on subsequent, max retries, non-retryable errors, generation mismatch |
| `MessagingInAppModule` | actor | ❌ |
| `NoOpNotificationInbox` | struct | ❌ |
| `Gist` | actor | ❌ |
| `GistDelegateImpl` | class | ❌ |
| `DefaultInAppMessageManager` | actor | ❌ |
| `QueueManager` | class | ❌ |
| `SseConnectionManager` | actor | ❌ |
| `CioSseLifecycleManager` | actor | ❌ |

### `CustomerIO_LiveActivities` (iOS)

| Type | Kind | Tests |
|---|---|---|
| `LiveActivitiesModule` | actor | ❌ |
| `CIOActivityAttributes` | protocol | ❌ marker protocol; no logic to test |
| `LiveActivityConfig` | struct | ✅ all defaults, init params |
| `LiveActivityConfigBuilder` | struct | ✅ (iOS 16.1+) URL, logLevel, register count, type names, value-type isolation |
| `ActivityTypeRegistration` | struct | ✅ indirectly via builder tests (activityTypeName, count) |
| `LiveActivityStorageMigration` | struct | ✅ migration runs, idempotent, stable ID |
| `StorageManager+LiveActivities` | extension | ✅ get/set/upsert/clear token per activity type |

### `CustomerIO_LiveUpdates` (Android)

| Type | Kind | Tests |
|---|---|---|
| `LiveUpdatesModule` | class/actor | ❌ |
| `LiveUpdateConfig` | data class | ❌ |
| `LiveUpdateEndReason` | enum | ❌ |
