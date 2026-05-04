# Feature Spec — Push Messaging

---

## Overview

The `CustomerIO_MessagingPush` module handles APNs and FCM push notifications
via the `PushTokenProvider` abstraction. It replaces the former split
`MessagingPushAPN` / `MessagingPushFCM` targets with a single unified target
where the token source is selected at configuration time. The split was
retired because all meaningful push logic (click handling, delivery tracking,
rich push, deduplication) is shared, and the provider-specific code in each
path is fewer than ~1 KB of machine code — not worth a separate link-time target.

See also: ADR 006 (no Firebase dependency).

---

## Reliability Guarantees

The old SDK lost delivery events when the notification service extension was
killed before a direct HTTP call could complete, and dropped click events that
arrived before `configure()` had run. The redesign addresses both:

- **No delivery event lost to process termination.** The extension writes
  delivery records to a shared App Group file rather than making a live HTTP
  call. The main app drains that file into the main event pipeline on next
  launch. Because `mutable-content: 1` is always set by the CIO server, the
  extension fires for every CIO notification and this queue covers all delivery
  events.
- **No push click lost to pre-configure timing.** `PushNotificationCenterRegistrar`
  is activated synchronously — before `application(_:didFinishLaunchingWithOptions:)`
  returns — via `CIOModule.preActivate(_:)`. It begins buffering any
  `UNUserNotificationCenter` callbacks immediately, holding their completion
  handlers uncalled. Once `configure()` completes, the registrar drains the
  buffer in order. The OS waits for the completion handler, so buffered clicks
  are never silently dropped.
- **The OS content handler is always called within the time budget.** SDK
  tracking and image download work runs on a deadline; notification display is
  never held hostage to upload success or image availability.
- **Delivery events are deduplicated by message ID.** If both the extension and
  the main app observe the same notification, only one event reaches the server.
- **The extension has no dependency on the full SDK.** `CustomerIO_MessagingPushNSE`
  links only against Foundation and UserNotifications — no actor, no SqlCipher,
  no configured key — so it can be included in a notification service extension
  target without pulling in the entire SDK.

---

## Configuration

### `PushTokenProvider` protocol

The single extension point for token delivery. Two paths:

```swift
public protocol PushTokenProvider: Sendable {
    func tokenFromAPNSData(_ deviceToken: Data) async throws -> String?
    func observeTokenRefresh(_ handler: @Sendable @escaping (String) -> Void) async
}
```

| Provider | `tokenFromAPNSData(_:)` | `observeTokenRefresh(_:)` |
|---|---|---|
| `APNPushProvider` (SDK-supplied) | Converts `Data` → lowercase hex string | No-op — token changes arrive via `didRegisterForRemoteNotifications` |
| App-supplied Firebase wrapper | Forwards `Data` to Firebase; returns FCM token (`nil` if not yet ready) | Calls Firebase's `onTokenRefresh` |

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

### Main app

```swift
SdkConfigBuilder(cdpApiKey: "…")
    .push {
        PushConfigBuilder(provider: APNPushProvider())  // or custom PushTokenProvider for FCM
            .autoTrackPushEvents(true)   // default: true — SDK registers as UNUserNotificationCenter delegate
            .showInForeground(true)
            .appGroupIdentifier("group.io.customer.myapp")
    }
    .build()
```

Module accessed at runtime via `cio.push`.

### Notification Service Extension

The NSE is implemented via the `CustomerIO_MessagingPushNSE` module — a
standalone package that links only against Foundation and UserNotifications
(no other SDK modules). This keeps the extension binary small and avoids
pulling unneeded dependencies into the extension process.

```swift
// NotificationService.swift
import CustomerIO_MessagingPushNSE

class NotificationService: CIONotificationServiceExtension {
    init() {
        super.init(
            cdpApiKey: "YOUR_CDP_API_KEY",
            region: .us,                               // optional, default .us
            appGroupId: "group.io.customer.myapp"      // optional but recommended
        )
    }
}
```

When an `appGroupId` is configured it must match the one set via
`PushConfigBuilder.appGroupIdentifier(_:)` in the main app. The `region`
parameter is ignored when `apiHost` is supplied directly.

---

## Module Startup Phases

### Phase 1 — `preActivate` (synchronous)

If `autoTrackPushEvents` is true, creates a `PushNotificationCenterRegistrar`
and calls `activate()` to register as the `UNUserNotificationCenter` delegate
in buffering mode. Events that arrive before `configure()` completes are
buffered and drained afterward.

### Phase 2 — `configure` (async)

In order:
1. Resolve log level from `pushConfig.logLevel ?? config.logLevel`.
2. Load persisted push token into in-memory `_currentToken` mirror.
3. Wire `_onTokenReceived` handler (persist token, upload device attributes).
4. Detect App Group container availability; update `sdk_meta` and device attribute if changed.
5. Wire `PushTokenProvider.observeTokenRefresh` → `applyToken`.
6. On UIKit: if `autoFetchDeviceToken`, call `UIApplication.shared.registerForRemoteNotifications()`.
7. Drain App Group delivery queue: delete `*.tmp` stragglers, decode/enqueue/delete each `*.json` record.
8. Subscribe to `ResetEvent` → clear `_currentToken`, clear storage, wipe App Group queue.
9. Wire `IOSPushEventListener` and call `registrar.setReady(listener:)` to drain buffer.

---

## Token Lifecycle

- **APNs token received** → `didRegisterForRemoteNotifications(withDeviceToken:)` → `PushTokenProvider.tokenFromAPNSData` → `applyToken` → persist + upload device attributes.
- **FCM token received** → app's `PushTokenProvider` conformance calls back via `observeTokenRefresh` → `applyToken`.
- **Token stored in-memory** in `_currentToken: Synchronized<String?>` for `nonisolated` access by `PushClickHandler`.
- **On `ResetEvent`**: token cleared from memory and storage; App Group queue wiped.

---

## Push Event Handling

### `IOSPushEventListener` (internal)

Receives `UNNotificationResponse` and `UNNotification` events. For each:

1. **Live Activity guard** — skip all tracking and forwarding for Live Activity payloads.
2. **CIO push detection** — check `userInfo[CIOKeys.Push.deliveryIDHeader]`.
3. **Deduplication** — `PushHistory` deduplicates clicks and displays by push ID + delivery date.
4. **Metric tracking** — `PushClickHandler` emits `"Report Delivery Event"` with `metric: "opened"` (click) or `metric: "delivered"` (foreground display). Device token sent as `"recipient"` property key.
5. **Deep link routing** — `DeepLinkUtil.open(url)` on `@MainActor`.
6. **Proxy forwarding** — all events (CIO and non-CIO) forwarded to `PushEventHandlerProxy`.

### `PushClickHandler` (internal)

Depends on `CIOTrackingClient` (not `CustomerIO` directly) for testability.

- `trackOpened(pushId:deliveryDate:)` — `metric: "opened"`
- `trackDelivered(pushId:deliveryDate:)` — `metric: "delivered"`
- Both include `recipient` (device token, if available) and `timestamp` (if delivery date known).

---

## Public API on `MessagingPushModule`

| Method | Concurrency | Description |
|--------|-------------|-------------|
| `didRegisterForRemoteNotifications(withDeviceToken:)` | `async throws` | Forward from app delegate |
| `didFailToRegisterForRemoteNotifications(withError:)` | `nonisolated` | Forward from app delegate; logs error |
| `userNotificationCenter(didReceive:withCompletionHandler:)` | `nonisolated` | Manual push handling (when `autoTrackPushEvents` is false) |
| `userNotificationCenter(willPresent:withCompletionHandler:)` | `nonisolated` | Manual push handling |
| `addEventHandler(_:)` | `nonisolated` | Register a `PushEventHandler` |
| `removeEventHandler(_:)` | `nonisolated` | Remove a `PushEventHandler` |
| `unregisterDevice()` | `nonisolated` | Emit `"Device Deleted"` to backend; retain local token |

---

## `unregisterDevice()`

Removes this device from the current user's profile on the backend, stopping
push delivery without affecting local identity, system push permission, or the
stored token.

**Intended use:** In-app opt-out control (not the system permission prompt).

**Re-registration behavior:**
- Automatic on the next `identify()` call when a profile change is detected.
- If the same user is already identified and wants to opt back in without logging
  out, call `registerDeviceToken(_:)` explicitly (TODO 16b).

**Implementation:** Emits `.trackSynthesized("Device Deleted", [deviceTokenKey: token])`
via the stored `_enqueueEvent` closure. Returns silently if no token is registered.

---

## Notification Service Extension

`CIONotificationServiceExtension` (in `CustomerIO_MessagingPushNSE`) is the
base class for the Notification Service Extension target. It handles:

### Delivery recording (two-phase)

On every CIO push received in the extension:

1. **Eager App Group write** — `DeliveryQueueRecord` is written to the App Group
   queue immediately via the `.tmp` → `.json` atomic rename. This is the reliable
   fallback: if the extension is killed before the upload completes, the main app
   drains the queue on next launch.

2. **Concurrent direct upload** — a `POST` to `<region.baseURL>/v1/track` (or
   `config.apiHost` when set) is started immediately after the App Group write,
   running concurrently with the image download. Payload:
   ```json
   {
     "anonymousId": "<deliveryId>",
     "event": "Report Delivery Event",
     "timestamp": "<ISO 8601>",
     "properties": { "recipient": "<token>", "metric": "delivered", "deliveryId": "<deliveryId>" }
   }
   ```
   Auth: HTTP Basic with `extensionCdpApiKey`. On HTTP 2xx, the App Group file is
   deleted — the main app will not re-process an already-delivered event. On any
   failure the file remains and is drained on next launch.

3. **`serviceExtensionTimeWillExpire()`** — cancels both the image download task
   (`_activeTask`) and the delivery upload task (`_deliveryUploadTask`), then calls
   the content handler with the best content assembled so far. The App Group file is
   already written so no delivery data is lost.

### App Group availability detection

On each `configure()`, the push module checks whether a valid shared App Group
container is accessible at runtime. The result is compared against the last
stored value in `sdk_meta` (`push_app_group_available`). A device attribute
update is only uploaded when the value changes or has never been recorded:

| Stored state | Current check | Action |
|---|---|---|
| Absent | Any | Store result; upload device attribute |
| `false` | `true` | Store `true`; upload device attribute |
| `true` | `false` | Store `false`; upload device attribute; log warning |
| Matches stored | — | No-op; no event fired |

This means the device attribute fires at most twice across the entire app
lifecycle: on first SDK run (no stored state), and if App Group availability
ever changes (e.g. a developer adds or removes the entitlement). Every other
launch is a two-boolean comparison with no network activity.

If App Group is unavailable, the module logs a warning and the extension falls
back to the background `URLSession` delivery path.

### Rich push image caching

The extension uses `URLSessionConfiguration.ephemeral` only for the
authenticated CIO API session (where writing credentials or API responses to
disk is undesirable). The public CDN session used for image downloads uses a
standard `URLSession` with a size-bounded `URLCache` backed by the App Group
container. This cache is accessible from both the extension and the main app,
so a bulk campaign sending the same image to a device multiple times avoids
redundant downloads.

### `CIONotificationServiceExtension.init` parameters

| Parameter | Default | Description |
|---|---|---|
| `cdpApiKey` | required | CDP API key used for upload auth |
| `region` | `.us` | Determines the upload base URL (ignored when `apiHost` is set) |
| `apiHost` | `nil` | Overrides the regional base URL for delivery uploads |
| `appGroupId` | `nil` | App Group container shared with the main app; enables reliable retry |

### Rich push image download

Downloaded via a cached `URLSession` with a 25-second timeout. Runs concurrently
with the delivery upload. Written to a temp file and attached as a
`UNNotificationAttachment`.

---

## Push Types and Delivery Tracking

### APNs payload flags

Two flags govern how a push is routed by the OS and whether the SDK can
intercept it for delivery tracking:

| Flag | Requires | Effect |
|---|---|---|
| `mutable-content: 1` | `alert` must be present | OS invokes the Notification Service Extension before displaying the notification |
| `content-available: 1` | `alert` must be absent | OS wakes the app in the background via `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` |

These two flags are mutually exclusive in practice. `mutable-content` requires
an `alert` element; `content-available` (silent push) requires its absence. A
payload carrying both cannot satisfy both requirements simultaneously. If
`mutable-content: 1` is present but no `alert` is included, the NSE is bypassed
and the push is treated as a plain notification.

### Delivery tracking by push type and app state

**`mutable-content` push (alert push with NSE present)**

The NSE is a separate OS-managed process. It runs independently of the main
app's state — force-quitting the main app has no effect on NSE invocation.

| App state | Delivery tracked | How |
|---|---|---|
| Foregrounded | ✅ (twice — NSE + `willPresent`) | NSE uploads; `willPresent` calls `trackDelivered` (backend deduplicates) |
| Backgrounded | ✅ | NSE uploads at display time |
| Force-quit | ✅ | NSE uploads at display time |

**`mutable-content` push (alert push, no NSE)**

| App state | Delivery tracked | How |
|---|---|---|
| Foregrounded | ✅ | `willPresent` fires → `trackDelivered` |
| Backgrounded | ❌ | Notification displayed directly; no callbacks fire until tap |
| Force-quit | ❌ | Same as backgrounded |

**No flags (plain alert push)**

Identical to `mutable-content` without an NSE. `mutable-content: 1` without a
configured NSE target is a no-op; the OS has nowhere to route the interception.

**`content-available` push (silent push)**

Silent pushes bypass `UNUserNotificationCenter` entirely. They are delivered to
`application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` only.
The SDK has no handler in this path — it is the host app's responsibility.

| App state | App woken | Notes |
|---|---|---|
| Foregrounded | ✅ | Callback fires immediately |
| Backgrounded | ⚠️ | Subject to Background App Refresh setting, Low Power Mode, and iOS per-app background budget |
| Force-quit | ❌ | iOS explicitly blocks background wakes for force-quit apps |

### `willPresent` vs `didReceive`

- **`willPresent`** — fires when an alert push arrives while the app is
  foregrounded. The delegate decides how to present it via
  `UNNotificationPresentationOptions`. Used to track `metric: "delivered"` for
  foreground receipt.
- **`didReceive`** — fires when the user taps or otherwise interacts with a
  notification. Fires regardless of what app state existed at display time.
  Used to track `metric: "opened"`.

### The NSE requirement for reliable delivery measurement

Without an NSE, delivery can only be measured when the app is foregrounded at
the time the push arrives. For backgrounded and force-quit states, the only
signal available is an open (tap), which conflates delivery with engagement.

An NSE configured with `mutable-content: 1` on every alert push is the only
mechanism for measuring true delivery rate — pushes received regardless of
whether they were opened. Whether CIO's backend sets `mutable-content: 1` on
all alert pushes or only those with rich content directly determines the
completeness of delivery data.

### `content-available` for population-level reachability

While not suitable for per-notification delivery tracking, `content-available`
pushes sent to the full token population can serve as a reachability probe —
measuring what fraction of tokens still reach an active, non-force-quit device.
This is a population-level health signal ("how many installs are reachable")
rather than a per-notification delivery signal. The ~10% non-response rate
typical of this approach reflects Background App Refresh restrictions and Low
Power Mode, not force-quit (which is rare in practice for most user populations).

---

## Outstanding Work

See `TODO.md` items 2 and 16 for remaining implementation tasks.
