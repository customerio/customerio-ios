# Messaging Push — Design Specification

**Status:** Stub — implementation not yet started
**Last updated:** March 18, 2026

---

## Overview

Push notification support lives in a single SPM target,
`CustomerIO_MessagingPush`, with one `MessagingPushModule` actor. The token
delivery mechanism — APNs hex conversion or Firebase FCM token exchange — is
selected at configuration time via the `PushTokenProvider` protocol:

```swift
// APN
SdkConfigBuilder(cdpApiKey: "…")
    .push {
        PushConfigBuilder(provider: APNPushProvider())
            .appGroupIdentifier("group.io.customer.myapp")
    }
    .build()

// Firebase — pass your PushTokenProvider conformance directly
SdkConfigBuilder(cdpApiKey: "…")
    .push {
        PushConfigBuilder(provider: MyFirebaseWrapper())
    }
    .build()
```

The SDK has no direct Firebase dependency. `PushTokenProvider` is a small
protocol that the app implements by wrapping its own `Firebase.Messaging`
instance. APN apps use the SDK-supplied `APNPushProvider` and write nothing
custom.

**Previous design (retired):** Two separate targets,
`CustomerIO_MessagingPushAPN` and `CustomerIO_MessagingPushFCM`, one per token
mechanism. Replaced by the unified module because all meaningful push logic
(click handling, delivery tracking, rich push, deduplication) is shared, and
the provider-specific code in each path is fewer than ~1 KB of machine code —
not worth a separate link-time target.

---

## Goals

- Accept a device token from the host app and persist it to `DeviceStore`.
- Upload a device-update event to the server whenever the token changes.
- Handle push notification click-through routing (open URL, dismiss).
- Support rich push (image / action buttons) via notification service extension.
- Subscribe to `ResetEvent` to clear the stored push token on `clearIdentify()`.
- Provide an ObjC-compatible surface for mixed-codebase apps.

### Delivery reliability goals

The old SDK lost delivery events when the notification service extension was
killed before a direct HTTP call could complete, and dropped click events that
arrived before `configure()` had run. The redesign must address both:

- **No delivery event lost to process termination.** The extension writes
  delivery records to a shared App Group file rather than making a live HTTP
  call. The main app drains that file into the main event pipeline on the next
  launch. Delivery tracking is never a blocking dependency for the extension
  process. Because `mutable-content: 1` is always set by the CIO server, the
  extension fires for every CIO notification and this queue covers all delivery
  events.
- **No push click lost to pre-configure timing.** `PushNotificationCenterRegistrar`
  is activated synchronously — before `application(_:didFinishLaunchingWithOptions:)`
  returns — via `CIOModule.preActivate(_:)`. It begins buffering any
  `UNUserNotificationCenter` callbacks immediately, holding their completion
  handlers uncalled. Once `configure()` completes and `MessagingPushModule` is
  ready, the registrar drains the buffer in order. The OS waits for the
  completion handler to be called, so buffered clicks are never silently
  dropped.
- **The OS content handler is always called within the time budget.** SDK
  tracking and image download work runs on a deadline; notification display is
  never held hostage to upload success or image availability.
- **Delivery events are deduplicated by message ID.** If both the extension and
  the main app observe the same notification, only one event reaches the server.
- **The extension has no dependency on the full SDK.** It uses only a thin,
  standalone module — no actor, no SqlCipher, no configured key — so it can be
  included in a notification service extension target without pulling in the
  entire SDK.

---

## Unified Module (`CustomerIO_MessagingPush`)

### `PushTokenProvider` protocol

The single extension point for token delivery. Two paths:

| Provider | `tokenFromAPNSData(_:)` | `observeTokenRefresh(_:)` |
|---|---|---|
| `APNPushProvider` (SDK-supplied) | Converts `Data` → lowercase hex string | No-op — token changes arrive via `didRegisterForRemoteNotifications` |
| App-supplied Firebase wrapper | Forwards `Data` to Firebase; returns FCM token (`nil` if not yet ready) | Calls Firebase's `onTokenRefresh` |

The protocol:

```swift
public protocol PushTokenProvider: Sendable {
    func tokenFromAPNSData(_ deviceToken: Data) async throws -> String?
    func observeTokenRefresh(_ handler: @Sendable @escaping (String) -> Void) async
}
```

A minimal Firebase wrapper:

```swift
class MyFirebaseWrapper: PushTokenProvider {
    func tokenFromAPNSData(_ deviceToken: Data) async throws -> String? {
        await messaging.setAPNSToken(deviceToken)
        return await messaging.fcmToken  // nil → will arrive via observeTokenRefresh
    }
    func observeTokenRefresh(_ handler: @Sendable @escaping (String) -> Void) async {
        messaging.onTokenRefresh(handler)
    }
}
```

### App delegate integration

**Use `startConfigure` — not a manual `Task { await configure() }`.**
`startConfigure` calls `activateModulesForLaunch` synchronously before
starting the configure task, which registers `PushNotificationCenterRegistrar`
as the `UNUserNotificationCenter` delegate before
`application(_:didFinishLaunchingWithOptions:)` returns. This is required by
Apple and is the only way to guarantee no cold-launch push click is missed.

If you must use the async `configure(_:)` path directly, call
`activateModulesForLaunch` synchronously first:

```swift
func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    // Recommended — handles pre-activation and configure in one call.
    cio.startConfigure(SdkConfigBuilder(cdpApiKey: "…").push { … }.build())

    // If using the async path instead, activateModulesForLaunch MUST come first:
    // let config = SdkConfigBuilder(cdpApiKey: "…").push { … }.build()
    // cio.activateModulesForLaunch(config)   // synchronous — must happen here
    // Task { try await cio.configure(config) }

    return true
}
```

The app also forwards three `UIApplicationDelegate` callbacks to `cio.push`:

```swift
func application(_ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Task { try await cio.push.didRegisterForRemoteNotifications(withDeviceToken: deviceToken) }
}

func application(_ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error) {
    cio.push.didFailToRegisterForRemoteNotifications(withError: error)  // nonisolated
}

func userNotificationCenter(_ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void) {
    // Handled automatically when autoTrackPushEvents is true.
    // For manual mode: cio.push.userNotificationCenter(center, didReceive: response, ...)
    completionHandler()
}
```

`didRegisterForRemoteNotifications(withDeviceToken:)` is `async throws`.
`didFailToRegisterForRemoteNotifications(withError:)` is `nonisolated` —
callable synchronously from any context.

### Token delivery

On `didRegisterForRemoteNotifications(withDeviceToken:)`:
1. Call `pushConfig.provider.tokenFromAPNSData(deviceToken)`.
2. If `nil` is returned, wait — the token will arrive via the refresh callback
   registered during `configure()`.
3. Persist the token string to `DeviceStore` (`device` table, key `push_token`).
4. Upload a device-update event if the token changed.

### Notification service extension

Apps add a `UNNotificationServiceExtension` target and forward two callbacks:

```swift
class NotificationService: UNNotificationServiceExtension {
    private var push: MessagingPushExtension?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        push = MessagingPushModule.configureForExtension(
            PushConfigBuilder.forExtension(cdpApiKey: "…")
                .appGroupIdentifier("group.io.customer.myapp")
        )
        push?.didReceive(request, withContentHandler: contentHandler)
    }

    override func serviceExtensionTimeWillExpire() {
        push?.serviceExtensionTimeWillExpire()
    }
}
```

`MessagingPushExtension` is a plain `final class` (not an actor) — extension
processes are single-threaded by convention and have no access to the main SDK.

### Current implementation state

`MessagingPushModule` is a stub actor. `PushTokenProvider`, `APNPushProvider`,
`PushConfig`, `PushConfigBuilder`, `SdkConfigBuilder+Push`, and
`CustomerIO+Push` are defined with correct signatures. `MessagingPushExtension`
is a stub. All `configure()` and token-delivery logic is `// TODO`.

---

## Notification Service Extension

The notification service extension is a separate binary target in the host app.
It runs in its own process, is launched by iOS when a push with
`mutable-content: 1` arrives, has up to ~30 seconds of execution time, and is
then killed — regardless of whether any async work has completed. It has no
shared memory with the main app.

**Assumption:** The CIO server always sets `mutable-content: 1` on every
generated push payload. Confirmed in `BuildPushMessage` at
`github.com/customerio/services/deliveries/clients/apns_relay.go`, where
`MutableContent: 1` is hardcoded unconditionally. The extension therefore fires
for every CIO notification without exception, and the App Group delivery queue
covers all CIO delivery events.

**Caveat:** Only this one server code path has been audited. If other server
paths exist that construct and send APNs payloads independently of
`apns_relay.go`, they must be verified to also set `mutable-content: 1` before
this assumption can be treated as complete. Until that audit is done, the
assumption should be considered confirmed for the known path only.

### App Group availability detection and device attribute

On each `configure()`, the push module checks whether a valid shared App Group
container is accessible at runtime:

```swift
FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId)
```

The result is compared against the last stored value in `sdk_meta`
(`push_app_group_available`). The attribute is only uploaded as a device
attribute update — **not** an identify event — when the value changes or has
never been recorded:

| Stored state | Current check | Action |
|---|---|---|
| Absent | Any | Store result; upload device attribute |
| `false` | `true` | Store `true`; upload device attribute |
| `true` | `false` | Store `false`; upload device attribute; log warning |
| Matches stored | — | No-op; no event fired |

This means the device attribute fires at most twice across the entire app
lifecycle: on first SDK run (no stored state), and if the App Group
availability ever changes (e.g. a developer adds or removes the entitlement).
Every other launch is a two-boolean comparison with no network activity.

If App Group is unavailable, the module logs a warning advising the developer
to configure an App Group entitlement and falls back to the background
`URLSession` delivery path described below.

---

### Two responsibilities

The extension performs two independent jobs:

**1. Delivery tracking** — Records that the notification reached the device.
This must survive process death; see [Delivery queue](#delivery-queue) below.

**2. Rich push image download** — If the payload contains a `cioImage.url`,
the extension downloads the image and attaches it to the notification content
before calling the OS content handler. This makes the notification "rich".
If the download fails or times out, the extension calls the content handler
with the unmodified text content — the notification always appears.

`serviceExtensionTimeWillExpire()` is the OS signal that the time budget is
nearly exhausted. The extension must cancel any in-flight image download and
call the content handler immediately with whatever content is ready.

### Delivery queue

The extension must not make a live HTTP call to record delivery. If the process
is killed while the request is in flight, the event is lost. The strategy
depends on whether an App Group is configured:

**Primary path — App Group available:**

Records are written as individual JSON files to a dedicated subdirectory of the
shared App Group container:

```
<AppGroupContainer>/io.customer.sdk/push-delivery/
```

The subdirectory is SDK-namespaced to avoid colliding with any other content the
host app places in the App Group container.

**Write (extension):**

1. Serialise the delivery record to JSON in memory.
2. Write to `delivery-<UUID>.tmp` in the subdirectory (creating the directory
   if it does not exist).
3. Rename to `delivery-<UUID>.json` — rename is atomic at the filesystem level.

The extension can be killed at any point. If killed before the rename, a `.tmp`
file is left behind; the main app discards it. If killed after the rename, the
`.json` file is complete and valid. There is no partial-record risk and no
cross-process locking is required — concurrent extension launches write to
different UUID-named files and never contend.

**Record format:**

```swift
struct DeliveryQueueRecord: Codable {
    let messageId: String    // CIO-Delivery-ID from the APNs payload
    let deviceToken: String  // recipient, for "Report Delivery Event" properties
    let timestamp: Date      // delivery timestamp
}
```

**Drain (main app, on `configure()`):**

1. Enumerate `*.tmp` files in the subdirectory and delete them all
   unconditionally — they are stragglers from extension processes killed before
   completing the write-then-rename, and contain no recoverable data.
2. Enumerate `*.json` files. For each:
   a. Read and decode the `DeliveryQueueRecord`.
   b. Construct a `"Report Delivery Event"` and enqueue it into the main event
      pipeline.
   c. Delete the file immediately after enqueue — do not batch-delete at the
      end, so a crash mid-drain does not orphan records.
3. The upload scheduler sends enqueued delivery events on its normal cadence.

**Reset (`clearIdentify()` / `ResetEvent`):**

Delete the entire `io.customer.sdk/push-delivery/` subdirectory. Delivery
records belong to the current profile; clearing identity makes them meaningless.
A fresh directory is created on the next extension write.

Delivery events are eventually consistent (uploaded on next app launch), which
is acceptable for analytics. The queue is offline-safe and process-death-safe.

**Fallback path — no App Group:**

If no App Group identifier is provided in config, or the container URL check
fails at runtime, the extension uses a background `URLSession`:

```swift
URLSessionConfiguration.background(withIdentifier: "io.customer.push-delivery.<cdpApiKey>")
```

Background session upload tasks are owned by the OS, not the extension process.
When the extension is killed, the OS continues the upload independently and
delivers the result to the containing app via
`application(_:handleEventsForBackgroundURLSession:completionHandler:)`. The
session identifier is derived deterministically from the CDP API key so the
main app can reconnect without additional configuration.

This path survives process termination but not extended offline periods — the
OS retries for a bounded window and then abandons the task. It is less
reliable than the App Group queue but significantly better than the old SDK's
approach of a plain URLSession call that died with the process.

| | App Group (primary) | Background URLSession (fallback) |
|---|---|---|
| Survives process kill | ✅ | ✅ |
| Survives offline | ✅ | Partial — OS retries |
| Additional app setup | App Group entitlement | `handleEventsForBackgroundURLSession` in AppDelegate |

### Rich push image caching

The old SDK used `URLSessionConfiguration.ephemeral` for all HTTP sessions in
the extension, including the public CDN session used for image downloads.
Ephemeral sessions store nothing to disk and discard their in-memory cache when
the process exits, meaning every notification re-downloads its image from
scratch.

**Design decision:** Use `URLSessionConfiguration.ephemeral` only for the
authenticated CIO API session (where writing credentials or API responses to
disk is undesirable). The public CDN session used for image downloads uses a
standard `URLSession` with a size-bounded `URLCache` backed by the App Group
container. This cache is accessible from both the extension and the main app,
so a bulk campaign sending the same image to a device multiple times — or
follow-up notifications sharing the same brand image — avoids redundant
downloads.

---

## Functionality Reference (from v1 SDK)

This section documents the full behaviour of the old SDK's `MessagingPush`
module as a baseline for the reimplementation. Design decisions specific to
the new SDK are noted inline.

---

### Configuration

`MessagingPushConfigOptions` / `MessagingPushConfigBuilder`:

| Option | Type | Default | Notes |
|---|---|---|---|
| `autoFetchDeviceToken` | Bool | `true` | SDK requests device token on init without requiring the app to call `registerForRemoteNotifications` manually |
| `autoTrackPushEvents` | Bool | `true` | Auto-track `opened` and `delivered` metrics |
| `showPushAppInForeground` | Bool | `true` | Display CIO notifications when the app is in the foreground |
| `cdpApiKey` | String | — | Required in extension initialiser only; not needed in the main app initialiser |
| `region` | Region | `.US` | Extension-only; controls which API host delivery metrics are sent to |
| `logLevel` | CioLogLevel | `.error` | Extension-only; main app uses the root SDK log level |

The extension initialiser (`initializeForExtension(withConfig:)`) is a
distinct code path from the main app initialiser (`initialize(withConfig:)`).
The extension path skips delegate registration and only sets up the HTTP
client and logger.

---

### Payload types

**`PushNotification` protocol** — framework-agnostic representation of any
push (CIO or third-party):

| Property | Type | Notes |
|---|---|---|
| `pushId` | String | Unique identifier. For APNs/FCM this is random. For local notifications it may be hard-coded and non-unique, hence `deliveryDate` is used as a secondary key |
| `deliveryDate` | Date? | Optional — not all `UserNotifications` callbacks supply it |
| `title`, `body` | String | Mutable (for extension content modification) |
| `data` | `[AnyHashable: Any]` | Full APNs payload user info |
| `attachments` | `[PushAttachment]` | Rich push file attachments |

CIO-specific extensions on `PushNotification`:

| Property | Source in payload | Notes |
|---|---|---|
| `isPushSentFromCio` | `data["CIO-Delivery-ID"]` presence | Gate for all CIO-specific handling |
| `cioDelivery` | `data["CIO-Delivery-ID"]`, `data["CIO-Delivery-Token"]` | ID and token needed for metric tracking |
| `cioImage` | `data["CIO"]["push"]["image"]` | HTTPS URL string for rich push image |
| `cioDeepLink` | `data["CIO"]["push"]["link"]` | Deep link URL string opened on push click |
| `cioAttachments` | `attachments` filtered by `"cio_sdk_"` prefix | SDK-managed attachment files only |
| `cioRichPushImageFile` | First `cioAttachment` | Local file URL after image download |

**`PushNotificationAction` protocol** — wraps a push event that was acted
upon:

| Property | Notes |
|---|---|
| `push` | The underlying `PushNotification` |
| `didClickOnPush` | `true` if `actionIdentifier == UNNotificationDefaultActionIdentifier`; `false` for dismiss |

**`CustomerIOParsedPushPayload`** — public-facing parsed payload, currently a
typealias for `UNNotificationWrapper`. Exposes `deepLink: URL?` and
`image: URL?` as the public API surface for manual push handling.

---

### UNUserNotificationCenter delegate management

The SDK takes over as the sole `UNUserNotificationCenter` delegate on
`configure()` (when `autoTrackPushEvents` is enabled). It does not swizzle.
Instead, `PushNotificationCenterRegistrar.activate()`:

1. Reads the app's existing delegate (if any) from
   `UNUserNotificationCenter.current().delegate`.
2. Wraps it in `UNUserNotificationCenterDelegateWrapper` and registers it
   with `PushEventHandlerProxy` so it continues to receive forwarded events.
3. Sets the SDK (`PushNotificationCenterRegistrarImpl`) as the new delegate.

This approach is compatible with other SDKs that also install a
`UNUserNotificationCenter` delegate, as long as they register before the CIO
SDK initialises. SDKs that register after (e.g. React Native Firebase) may
need to use the manual forwarding path instead.

---

### Push event handler pipeline

Events from `UNUserNotificationCenterDelegate` flow through three layers:

```
UNUserNotificationCenter (OS)
    │
    │  Note: apns-push-type: liveactivity pushes are intercepted by the OS
    │  before reaching this point and are NEVER delivered here. See below.
    │
    ▼
PushNotificationCenterRegistrarImpl   (sole UNUserNotificationCenterDelegate)
    │
    ▼
IOSPushEventListener                  (CIO's PushEventHandler)
    │  Live Activity payload? → exit immediately (see Live Activity guard below)
    │  CIO push? → handle, then forward
    │  Non-CIO push? → forward only
    ▼
PushEventHandlerProxy                 (fan-out to all registered handlers)
    │
    ▼
[3rd-party SDK wrappers, app delegate wrapper, ...]
```

#### Live Activity payload guard

`apns-push-type: liveactivity` pushes are not delivered through
`UNUserNotificationCenter` and therefore cannot appear in this pipeline under
normal circumstances. However, if the backend includes an `alert` in a Live
Activity update payload and the user taps the resulting notification banner,
the tap is delivered here as a standard `didReceive` callback.

Live Activity payloads are identified by the presence of `aps.event` in the
payload, which no standard CIO push payload includes:

```swift
func isLiveActivityPayload(_ userInfo: [AnyHashable: Any]) -> Bool {
    guard let aps = userInfo["aps"] as? [String: Any] else { return false }
    return aps["event"] != nil   // "update", "end", or "start"
}
```

`IOSPushEventListener` calls this check as the first step in both
`onPushAction` and `shouldDisplayPushAppInForeground`. If it returns `true`,
the listener exits immediately without tracking a click metric, routing a deep
link, or forwarding to the proxy. The completion handler is called with a
no-op result so the OS is not left waiting.

**`PushEventHandlerProxy`** fans events out to all registered handlers
sequentially on `@MainActor`, awaiting each completion handler before
proceeding. Guards against handlers that call the completion handler more than
once (observed with React Native Firebase). For `shouldDisplayPushAppInForeground`,
uses OR semantics across third-party handlers — any `true` result means show
the push. For CIO-originated notifications, the SDK's own
`showPushAppInForeground` config value overrides all third-party results.

**`IOSPushEventListener`** — CIO's concrete handler:

`onPushAction(_:completionHandler:)`:
1. Live Activity guard: if `aps.event` is present → call `completionHandler()` and return. Live Activity alert taps must not be tracked as push clicks or trigger deep link routing.
2. Guard: `deliveryDate` must be present.
3. Check `PushHistory` — exit early if already handled (prevents double-processing when 3rd-party SDKs forward events back to CIO).
4. Non-CIO push → forward to proxy only, do not handle.
5. CIO push → `cleanupAfterPushInteractedWith` (delete local image files).
6. If `didClickOnPush` → `trackPushMetrics` (record `opened` metric).
7. Forward to proxy, and only after proxy completes → `handleDeepLink`. Deep link is deliberately deferred until the app's own handlers have finished, to avoid navigating away before the app has processed the event.

`shouldDisplayPushAppInForeground(_:completionHandler:)`:
1. Live Activity guard: if `aps.event` is present → call `completionHandler([])` and return. The OS handles Live Activity alert display; the SDK must not interfere.
2. Guard: `deliveryDate` must be present.
3. Check `PushHistory` — exit early if already handled.
4. Non-CIO push → forward to proxy.
5. CIO push → forward to proxy, then call `completionHandler(showPushAppInForeground)` using SDK config value regardless of proxy result.

---

### Push history / deduplication

`PushHistory` is an in-memory, thread-safe store that prevents a push event
from being processed more than once per app session. It is keyed by
`(pushId, deliveryDate)` — the delivery date is necessary because local
notifications can share a hard-coded `pushId`.

Separate histories are maintained for `didReceive` (click/dismiss) and
`willPresent` (foreground display) events, as both may fire for the same push.

This is an in-memory store only; it does not survive process restart. A push
that arrives, is not acted on, and then the app is killed will be processed
again correctly on the next launch.

---

### Click handling

`PushClickHandler` performs three operations on push click:

1. **`trackPushMetrics(for:)`** — calls `trackMetric(deliveryID:event:deviceToken:)`
   with `event: .opened`. No-op if `cioDelivery` is absent.
2. **`handleDeepLink(for:)`** — extracts `cioDeepLink.url` and routes via
   `DeepLinkUtil.handleDeepLink(_:)`. No-op if no deep link is present.
   See [Deep link routing](#deep-link-routing) for the three-tier strategy.
3. **`cleanupAfterPushInteractedWith(for:)`** — deletes all local files
   attached to the push (identified by the `"cio_sdk_"` prefix on the
   attachment identifier). Rich push images are downloaded to a temporary
   location; this cleans up those files once the notification is no longer
   displayed.

Cleanup happens **before** deep link routing, ensuring files are deleted even
if deep link navigation leaves the app.

---

### Deep link routing

`DeepLinkUtil.handleDeepLink(_:)` applies a three-tier routing strategy in
order:

1. **Explicit callback** — if the app registered a `deepLinkCallback` closure
   via `setDeepLinkCallback(_:)`, call it and return. This is the recommended
   path for apps that need custom navigation logic (e.g. in-app routing
   without opening Safari).

2. **Universal link** — if the URL scheme is `http` or `https`, call
   `UIApplication.shared.continue(NSUserActivity(webpageURL: url))`. This
   triggers the app's `application(_:continue:restorationHandler:)` delegate
   method, which is the standard iOS path for universal link handling.

3. **Fallback** — call `UIApplication.shared.open(url)`. The OS routes the URL
   to whichever app handles the scheme (Safari for `https`, a registered scheme
   handler for custom schemes, etc.).

No routing occurs if `cioDeepLink` is absent from the payload.

`setDeepLinkCallback(_:)` is an SPI (not part of the public API surface).
It is provided for host apps that need to intercept all CIO push deep links
without relying on the system open path. Firebase-based integrations, for
example, typically register a callback here so that Firebase Dynamic Links can
be resolved before the URL is opened.

---

### Manual push handling

For apps that cannot or do not want the SDK to auto-register as the
`UNUserNotificationCenter` delegate (`autoTrackPushEvents: false`), the SDK
exposes manual forwarding methods:

```swift
// Returns true if the SDK handled it (CIO push); false if not (caller must call completionHandler)
MessagingPush.shared.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)

// Returns a parsed payload if CIO push; nil if not
MessagingPush.shared.userNotificationCenter(center, didReceive: response) -> CustomerIOParsedPushPayload?
```

The two-overload design allows apps that parse the payload themselves (e.g.
to read `deepLink` or `image` properties) to do so without also triggering
the SDK's automatic click tracking.

---

### Metric tracking

Three events are tracked as push metrics:

| Metric | When | Source |
|---|---|---|
| `delivered` | Extension fires for a CIO push | `trackMetricFromNSE` in extension |
| `opened` | User taps the notification | `trackPushMetrics` in click handler |
| `converted` | Reserved (not yet used) | — |

**Extension delivery metric wire format** (sent directly to API from
extension in v1; to be replaced by App Group queue in v2):

```json
{
  "anonymousId": "<deliveryId>",
  "event": "Report Delivery Event",
  "properties": {
    "recipient": "<deviceToken>",
    "metric": "delivered",
    "deliveryId": "<deliveryId>"
  }
}
```

Endpoint: `POST /v1/track` (CDP region-specific host).

---

### Token management

- `registerDeviceToken(_:)` — deduplicates against the token stored in
  `DeviceStore`; only sends a device-update event if the token has changed.
  This prevents redundant uploads on every app launch.
- `deleteDeviceToken()` — removes the token from the server (called on
  `clearIdentify()`). Only sent if a token was previously registered;
  no-op if `DeviceStore` holds no token.

#### Device-update event wire format

Token registration and updates are sent as a standard track event on the CDP
pipeline — **not** a dedicated device registration endpoint:

```json
{
  "event": "Device Created or Updated",
  "properties": {
    "token": "<hexDeviceToken>",
    "platform": "ios",
    "os_version": "18.1",
    "app_version": "1.0.0",
    "network_bluetooth": true,
    "network_cellular": false,
    "network_wifi": true,
    "screen_width": 390,
    "screen_height": 844,
    "ip": "auto",
    "timezone": "America/Chicago"
  }
}
```

The token itself travels as a property on the event. OS/network/screen/timezone
attributes are added by a context plugin (`DeviceContextualAttributes`) that
enriches every `"Device Created or Updated"` event automatically. Custom device
attributes set via `setDeviceAttributes()` are merged into `properties` by the
same mechanism.

#### Token deletion wire format

Token deletion is a standard track event with no additional payload:

```json
{
  "event": "Device Deleted",
  "properties": {}
}
```

Only sent if a token was previously stored. The server uses this event to
dissociate the device from the current profile.

#### Token lifecycle on profile change

When `identify()` is called with a new profile while a token is already
registered:

1. Send `"Device Deleted"` to remove the token from the previous profile.
2. Call `identify()` to associate the new profile.
3. Re-register the existing token to the new profile by sending
   `"Device Created or Updated"` again.

This ensures the device token is always owned by exactly one profile, and that
pushes sent after `identify()` reach the new profile immediately.

---

## Outstanding Work

Items are ordered by dependency. See also `TODO.md`.

### 1. `DeviceStore` — token persistence

`setDeviceAttributes()` on `CustomerIO` is currently a no-op stub. Completing
this unblocks push token delivery:

- Persist push token and custom device attributes to the `device` table.
- Forward attributes to `EventEnricher` so they appear in event context.
- Upload a device-update event when the token or attributes change.

### 2. `MessagingPushModule` — full implementation

Depends on `DeviceStore`:

- `preActivate(_:)` (called synchronously by `activateModulesForLaunch`, before
  `didFinishLaunchingWithOptions` returns):
  - If `autoTrackPushEvents`, create `PushNotificationCenterRegistrar` and call
    `activate()` — sets `UNUserNotificationCenter.current().delegate` to the
    registrar. The registrar starts in buffering mode: it stores received
    `(UNNotificationResponse, completionHandler)` pairs without calling the
    completion handler, so the OS waits.
- `configure()`:
  - Detect App Group availability; compare against `sdk_meta`
    `push_app_group_available`; upload device attribute if changed.
  - If `autoFetchDeviceToken` is `true`, hop to the main actor and call
    `registerForRemoteNotifications()`:
    ```swift
    await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    ```
    This is fire-and-forget; the token arrives asynchronously via
    `didRegisterForRemoteNotifications`.
  - Call `pushConfig.provider.observeTokenRefresh` to wire token refresh →
    `DeviceStore`.
  - Subscribe to `ResetEvent` → delete device token from `DeviceStore`; wipe
    `io.customer.sdk/push-delivery/` subdirectory.
  - Drain the App Group delivery queue: delete `*.tmp` stragglers, then for
    each `*.json` record: decode → enqueue `"Report Delivery Event"` → delete
    file. Process and delete one at a time (no batch delete).
  - At the end of `configure()`, call `registrar.setReady(module: self)` to
    drain the pre-configure buffer: any buffered responses are forwarded to the
    now-ready push event pipeline in order, with their completion handlers
    called after processing.
- `didRegisterForRemoteNotifications(withDeviceToken:)`: call provider, deliver
  result to `DeviceStore`, upload device-update event.
- `didFailToRegisterForRemoteNotifications(withError:)`: log via SDK logger.

Components to implement (see [Functionality Reference](#functionality-reference-from-v1-sdk)):

- Payload types: `PushNotification`, `CustomerIOParsedPushPayload`,
  `PushNotificationAction`, `UNNotificationWrapper`
- `PushEventHandler` + `PushEventHandlerProxy`
- `PushNotificationCenterRegistrar` — with pre-configure buffer (`Synchronized`-
  protected `[(UNNotificationResponse, () -> Void)]`) and `setReady(module:)`
  drain method
- `iOSPushEventListener`
- `PushClickHandler` (metric tracking, deep link, file cleanup)
- `PushHistory` (in-memory deduplication store)
- Manual push handling overloads

### 3. `MessagingPushExtension` — full implementation

- On receipt: create `io.customer.sdk/push-delivery/` directory if absent;
  write record to `delivery-<UUID>.tmp`; rename to `delivery-<UUID>.json`.
- Fall back to background `URLSession` upload if no App Group is configured.
- Download and attach rich push images using a cached `URLSession` (standard
  config, App Group cache directory).
- Cancel image downloads and call content handler in
  `serviceExtensionTimeWillExpire()`.

**Note:** Add drain and reset logic to `MessagingPushModule.configure()` and
`ResetEvent` handler respectively (see item 2 above).

---

## Open Questions

### Resolved

- **Device-update event format.** `"Device Created or Updated"` — standard
  CDP track event, not a dedicated endpoint. Properties include device token,
  OS/network/screen/timezone contextual attributes, and any custom device
  attributes. See [Token management](#token-management).
- **Token deletion format.** `"Device Deleted"` — standard CDP track event
  with no additional payload. See [Token management](#token-management).
- **Token lifecycle on profile change.** Delete old token → identify new
  profile → re-register token. See [Token management](#token-management).
- **Deep link routing.** Three-tier: explicit callback → universal link →
  system open. See [Deep link routing](#deep-link-routing).
- **`autoFetchDeviceToken` behavior.** Retained from v1. When `true`, SDK
  calls `UIApplication.shared.registerForRemoteNotifications()` automatically
  during `configure()` via `await MainActor.run { … }` to satisfy the
  `@MainActor` requirement without blocking the configure actor.
- **Rich push in notification service extension.** Extension uses a thin
  standalone module (no full SDK dependency), writes delivery records to a
  shared App Group file, and uses a separate cached URLSession for CDN image
  downloads. See [Notification Service Extension](#notification-service-extension).
- **ObjC bridge for push.** Not required. Push is always configured from Swift.
- **Delivery event `anonymousId` field.** In v1 the extension set `anonymousId`
  to the `deliveryId` because it had no access to SDK state. In v2, delivery
  records are drained through the main app, which has a real anonymous ID.
  The difference is accepted: delivery events in v2 carry the SDK's actual
  anonymous ID in the envelope, matching the format of every other event the
  SDK sends. The `deliveryId` remains in `properties.deliveryId` for server-
  side message resolution.
- **Delivery queue file format.** One JSON file per record, written via
  write-then-atomic-rename (`*.tmp` → `*.json`) to
  `<AppGroupContainer>/io.customer.sdk/push-delivery/`. No locking required.
  Drain on `configure()` deletes `.tmp` stragglers first, then processes and
  deletes each `.json` one at a time. Directory wiped on `ResetEvent`.
  See [Delivery queue](#delivery-queue).
- **Pre-configure push click buffering.** `CIOModule.preActivate(_:)` is called
  synchronously by `CustomerIO.activateModulesForLaunch(_:)` before
  `didFinishLaunchingWithOptions` returns. `MessagingPushModule.preActivate`
  creates `PushNotificationCenterRegistrar` and registers it as the
  `UNUserNotificationCenter` delegate at that point. The registrar buffers
  received responses (holding completion handlers uncalled) until
  `configure()` completes and calls `registrar.setReady(module:)`. `startConfigure`
  calls `activateModulesForLaunch` automatically; async `configure()` users must
  call it manually. See [App delegate integration](#app-delegate-integration).
