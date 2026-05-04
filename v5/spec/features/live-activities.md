# Live Activities — Feature Specification

## Overview

The `CustomerIO_LiveActivities` module tracks iOS Live Activities (ActivityKit,
iOS 17.2+) on behalf of the host app, reporting state changes and token
registrations to the Customer.io backend.

The host app is responsible only for ActivityKit calls — starting and ending
activities. All network communication with the Customer.io backend is the SDK's
responsibility. The host app must not make its own requests to CIO Live Activity
endpoints.

ActivityKit generates its own push tokens independently of push notification
permission, so `CustomerIO_LiveActivities` works standalone via direct APNs
delivery. Registering `CustomerIO_MessagingPush` alongside it is optional —
it is required only when the partner's push configuration routes iOS notifications
through Firebase (FCM). FCM delivery of Live Activity pushes requires a device
FCM registration token, which the push module registers. Without push, all Live
Activity functionality operates normally via direct APNs delivery.

---

## Scope

| Capability | Included |
|---|---|
| Content state change reporting | Yes |
| Activity end/dismiss reporting | Yes |
| Instance push token registration | Yes |
| Instance push token rotation detection | Yes |
| Push-to-start token registration | Yes |
| Push-to-start token rotation detection | Yes |
| Persisting push-to-start token state across launches | Yes |
| Remote activity start (push-to-start) | No (server-driven) |
| Remote activity update via APNs | No (server-driven) |
| Rich push attachment for Live Activities | No |

---

## Platform Requirements

- iOS 17.2 or later (required for `Activity.pushToStartTokenUpdates`)
- `CustomerIO_MessagingPush` is optional — required only when the partner routes iOS push through Firebase (FCM)

`LiveActivitiesModule` itself compiles on all supported platforms. On macOS or
iOS < 17.2 it is a no-op — it registers its storage migration and responds to
`ResetEvent`, but performs no ActivityKit observation.

`LiveActivityConfigBuilder` and `SdkConfigBuilder.liveActivities` are
conditionally compiled with `#if os(iOS)` and are **not available on macOS**.
On iOS, both carry an `@available(iOS 17.2, *)` restriction.

---

## Protocol Requirements

All `ActivityAttributes` types registered with the SDK must conform to
`CIOActivityAttribute`:

```swift
public protocol CIOActivityAttribute: ActivityAttributes {
    /// The stable, partner-supplied identifier the Customer.io backend uses to
    /// address this specific activity instance in API routes and webhook callbacks.
    ///
    /// Set this to a value that already exists in your backend domain — for example,
    /// an order ID or shipment number — so that Customer.io webhook callbacks map
    /// directly to your own entities without a separate UUID→ID lookup.
    ///
    /// Requirements:
    /// - Stable for the lifetime of the activity — must not change after the
    ///   activity is created.
    /// - Globally unique within the Customer.io site identified by `cdpApiKey` —
    ///   a duplicate will cause the server to overwrite the earlier registration.
    /// - The SDK percent-encodes this value when embedding it in URL paths; prefer
    ///   printable ASCII (alphanumerics, hyphens, underscores).
    var activityInstanceId: String { get }
}
```

Example conformance:

```swift
struct OrderActivityAttributes: CIOActivityAttribute {
    let activityInstanceId: String   // e.g. "order-9876" — your domain entity ID
    let customerName: String
    struct ContentState: Codable & Hashable { … }
}
```

---

## Configuration

```swift
// Standalone — no push required
SdkConfigBuilder(cdpApiKey: "…")
    .liveActivities {                                      // iOS 17.2+ only
        LiveActivityConfigBuilder(baseURL: URL(string: "https://…"))
            .register(OrderActivityAttributes.self, identifier: "io.yourapp.liveactivities.order")
            .register(ShipmentActivityAttributes.self, identifier: "io.yourapp.liveactivities.shipment")
    }
    .build()

// With push — required for Firebase (FCM) push configuration
SdkConfigBuilder(cdpApiKey: "…")
    .push {
        PushConfigBuilder(provider: APNPushProvider())
    }
    .liveActivities {
        LiveActivityConfigBuilder(baseURL: URL(string: "https://…"))
            .register(OrderActivityAttributes.self, identifier: "io.yourapp.liveactivities.order")
            .register(ShipmentActivityAttributes.self, identifier: "io.yourapp.liveactivities.shipment")
    }
    .build()
```

Passing `nil` (or calling `LiveActivityConfigBuilder()` with no arguments) produces
a no-op module that compiles and runs but makes no network requests. This is the
intended state during development before a backend endpoint has been provisioned.

### `LiveActivityConfig` fields

| Field | Type | Default | Notes |
|---|---|---|---|
| `liveActivitiesBaseURL` | `URL?` | `nil` | **Temporary.** Will be derived from `SdkConfig.region` once backend paths are finalised. Module is a no-op when `nil`. |
| `logLevel` | `CIOLogLevel?` | `nil` | Falls back to `SdkConfig.logLevel` when nil. |

### `LiveActivityConfigBuilder` methods

| Method | Description |
|---|---|
| `init(baseURL: URL? = nil)` | Create a builder. Pass `nil` (or omit) for a no-op module. |
| `baseURL(_:)` | Fluent override of the base URL. |
| `logLevel(_:)` | Module-level log override. |
| `register(_ type:, identifier:)` | Register a `CIOActivityAttribute` conformance for observation. `identifier` is a stable reverse-DNS string (e.g. `"io.yourapp.liveactivities.order"`) used in the push-to-start API path and matched server-side. Must not change after shipping. |
| `appGroup(_ identifier:)` | Set the AppGroup container identifier for asset sharing with the widget extension. |
| `registerAsset(_ key:, at url:)` | Pre-load a bundle asset into the AppGroup container by explicit URL. |
| `registerAsset(_ key:, bundleResource:, withExtension:)` | Pre-load a named bundle resource into the AppGroup container. Calls `fatalError` at launch if the resource is not found in the bundle. |

---

## Accessing the Module

After SDK configuration, the Live Activities module is accessible via the root
`CustomerIO` instance:

```swift
cio.liveActivities
```

Accessing `cio.liveActivities` before the module is registered in
`SdkConfigBuilder` triggers a `fatalError` at runtime.

---

## Asset Library (Widget Extensions)

The module can pre-load image assets from the app bundle into a shared AppGroup container,
making them available to the widget extension at render time without a network request.

```swift
LiveActivityConfigBuilder(baseURL: url)
    .appGroup("group.io.yourapp.liveactivities")
    .registerAsset("hero_image", bundleResource: "HeroImage", withExtension: "png")
    .registerAsset("logo", at: Bundle.main.url(forResource: "Logo", withExtension: "svg")!)
```

Assets are synced at `configure()` time. Changed assets (detected via SHA-256 hash) are
re-copied; unchanged assets are skipped. A sync failure logs a warning and does not prevent
activity observation from starting. In the widget extension, assets are retrieved by key
via `CIOAssetLibrary`.

---

## Activity Observation

For each registered activity type `T`, the module starts two concurrent observation
streams after `configure()`. As activities are observed, the module emits
`LiveActivityInfo` values to the `observedActivities` stream.

### `LiveActivityInfo`

```swift
public struct LiveActivityInfo: Sendable {
    public let activityId: String      // ActivityKit-assigned activity ID (`Activity<T>.id`)
    public let activityInstanceId: String  // partner-supplied identifier from `attributes.activityInstanceId`
    public let activityType: String    // stable reverse-DNS identifier from `register(_:identifier:)`
    public let installationId: String  // stable per-install UUID
    public let userId: String          // identified user ID, or anonymous ID
}
```

`activityId` is the opaque ID assigned by ActivityKit — useful for local ActivityKit
correlation but not used in Customer.io server routes. `activityInstanceId` is the
partner-supplied identifier from the activity's `CIOActivityAttribute.activityInstanceId`
property; this is the value the Customer.io backend uses in all instance-level API paths
and in webhook callbacks to the partner's backend.

### `observedActivities` stream

```swift
for await info in cio.liveActivities.observedActivities {
    // forward to the host app's own backend
}
```

The stream uses `.bufferingNewest(10)` — up to 10 events are buffered for late
subscribers. It fires for all creation paths (host-app-initiated, push-to-start,
and launch replay); handlers must be idempotent. On `ResetEvent` the stream is
finished and a new one is created immediately — the host app must re-subscribe.

### 1. Push-to-start token stream

`Activity<T>.pushToStartTokenUpdates` — fires on first observation (current token)
and again on each rotation. The module:

1. Compares the incoming token hex to the last-registered value in local storage.
2. If changed (or no prior record), sends `PUT /v1/live_activities/registration/{activityType}`.
3. Persists the new token hex and timestamp in `live_activity_push_to_start`.

`activityType` is the stable reverse-DNS `identifier` declared in `register(_:identifier:)`.

### 2. Activity instance stream

`Activity<T>.activityUpdates` — fires for each current activity on startup and each
new activity as it is created. When each activity is first observed, a `LiveActivityInfo`
is emitted to `observedActivities`. The module then starts three child tasks:

- **Instance token task:** `activity.pushTokenUpdates` — fires immediately with the
  current token and again on each rotation. Sends
  `PUT /v1/live_activities/{activityInstanceId}/push_token` so the backend knows which APNs
  token to use when pushing updates to this specific activity instance. `activityInstanceId`
  is read from `activity.attributes.activityInstanceId`.

- **Content state task:** `activity.contentStateUpdates` — sends
  `PUT /v1/live_activities/{activityInstanceId}` with a JSON envelope containing the
  encoded `ContentState` on each change.

- **Lifecycle task:** `activity.activityStateUpdates` — sends
  `DELETE /v1/live_activities/{activityInstanceId}` when the state reaches `.ended`,
  `.dismissed`, or `.stale`.

The instance token task must begin observation before the content state and
lifecycle tasks so that the backend has a valid token before any update or end
events arrive.

---

## HTTP API

All SDK surface requests carry:

| Header | Value |
|---|---|
| `Authorization` | `Basic <base64("cdpApiKey:")>` |
| `User-Agent` | The SDK's standard `User-Agent` string. |

Retry policy: `5xx` → up to 3 attempts with exponential backoff. `4xx` → no retry.

The SDK calls four endpoints as part of normal live activity lifecycle management:

| Endpoint | When called |
|---|---|
| `PUT /v1/live_activities/registration/{activityType}` | Push-to-start token received or rotated (iOS); at configure time (Android). |
| `PUT /v1/live_activities/{activityInstanceId}/push_token` | Activity instance starts; instance token rotates. |
| `PUT /v1/live_activities/{activityInstanceId}` | Host app updates content state locally. |
| `DELETE /v1/live_activities/{activityInstanceId}` | Activity ends, is dismissed, or goes stale. |

For full request/response shapes, field definitions, and error behaviour, see
[`spec/interfaces/live-activity-sdk-api.md`](../interfaces/live-activity-sdk-api.md).

> All endpoint paths are provisional pending backend confirmation. The
> `liveActivitiesBaseURL` config field allows the SDK to ship before final paths
> are locked.

---

## System Architecture

Three parties participate in every Live Activity update:

```
┌──────────────────┐         ┌──────────────────────┐         ┌────────────────┐
│   Device / SDK   │         │    CIO Backend        │         │  App's backend │
│                  │         │                       │         │  / campaigns   │
│  1. Activity     │         │                       │         │                │
│     starts       │         │                       │         │                │
│                  │──(PUT)──▶  /live_activities/    │         │                │
│  2. Token        │         │  {activityInstanceId} │         │                │
│     registered   │         │  (stores token,       │         │                │
│                  │         │   profile, type)      │         │                │
│                  │         │                       │◀──────── │  3. Trigger    │
│                  │         │  Looks up token for   │  send   │     update via  │
│                  │         │  this activity        │  order  │     CIO API    │
│                  │         │                       │         │                │
│  4. APNs/FCM     │◀────────│  Sends push with      │         │                │
│     delivers     │  push   │  liveactivity type    │         │                │
│     update       │         │                       │         │                │
│                  │         │                       │         │                │
│  5. Activity     │         │                       │         │                │
│     ends; SDK    │──(DEL)──▶  /live_activities/    │         │                │
│     deregisters  │         │  {activityInstanceId} │         │                │
└──────────────────┘         └──────────────────────┘         └────────────────┘
```

The SDK's role is steps 2 and 5. Steps 3 and 4 happen entirely in the backend
and are outside the SDK's scope.

---

## Analytics Events

All analytics events flow through the standard `track` pipeline (batched,
encrypted queue). Only `properties` are shown below; all events include the
standard envelope fields (`anonymousId`, `userId`, `timestamp`, `messageId`).

**Live Activity Started** — emitted when the first token from `pushTokenUpdates`
is received.

```json
{
  "event": "Live Activity Started",
  "properties": {
    "activity_id":   "abc123",
    "activity_type": "io.yourapp.liveactivities.order",
    "platform":      "ios"
  }
}
```

**Live Activity Ended** — emitted when `activityDidEnd` is called or when the
activity state stream reaches a terminal state.

```json
{
  "event": "Live Activity Ended",
  "properties": {
    "activity_id":   "abc123",
    "activity_type": "io.yourapp.liveactivities.order",
    "reason":        "user_dismissed",
    "platform":      "ios"
  }
}
```

`reason` values: `"unknown"`, `"user_dismissed"`, `"expired"`, `"programmatic"`.

**Live Activity Tapped** — emitted when `activityDidReceiveInteraction` is
called.

```json
{
  "event": "Live Activity Tapped",
  "properties": {
    "activity_id":   "abc123",
    "activity_type": "io.yourapp.liveactivities.order",
    "platform":      "ios"
  }
}
```

**Push-to-Start Token Registered** — emitted once per activity type when the
first push-to-start token is received. Token rotation is silent — no event.

```json
{
  "event": "Live Activity Push-to-Start Token Registered",
  "properties": {
    "activity_type": "io.yourapp.liveactivities.order",
    "platform":      "ios"
  }
}
```

**Live Update Shown** (Android) — emitted when `trackNotification` is called.

```json
{
  "event": "Live Update Shown",
  "properties": {
    "notification_id": 1001,
    "activity_type":   "io.yourapp.liveactivities.order",
    "platform":        "android"
  }
}
```

**Live Update Ended** (Android) — emitted when `notificationEnded` is called.

```json
{
  "event": "Live Update Ended",
  "properties": {
    "notification_id": 1001,
    "activity_type":   "io.yourapp.liveactivities.order",
    "reason":          "completed",
    "platform":        "android"
  }
}
```

**Live Update Interacted** (Android) — emitted when `notificationInteracted`
is called.

```json
{
  "event": "Live Update Interacted",
  "properties": {
    "notification_id": 1001,
    "activity_type":   "io.yourapp.liveactivities.order",
    "action_id":       "view_order",
    "platform":        "android"
  }
}
```

**Live Update Unrecognized Type** (Android) — emitted when the SDK receives an
FCM message with `cio_live_update: true` and a `cio_activity_type` value not
present in any registered `LiveUpdateConfig`. Surfaces backend misconfiguration.

```json
{
  "event": "Live Update Unrecognized Type",
  "properties": {
    "activity_type": "unknown_type",
    "platform":      "android"
  }
}
```

iOS note: The SDK has no visibility into push-to-start rejections. If
`attributes-type` in the APNs payload does not match the app's Swift type name,
the OS silently rejects the push-to-start attempt.

---

## Push Routing and Coexistence with MessagingPush

### Why no filtering is needed

`apns-push-type: liveactivity` is a distinct APNs push type. The OS routes it
directly to the ActivityKit layer before any app or extension code runs:

- `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` is **not called**
- `UNUserNotificationCenter` delegate methods (`willPresent`, `didReceive`) are **not called**
- The Notification Service Extension is **not invoked**

`MessagingPushModule` installs itself as the `UNUserNotificationCenter` delegate
and responds to `didReceiveRemoteNotification`. Because neither callback fires
for `liveactivity` push types, there is no intersection and no routing logic is
required in either module.

### The alert edge case

If the CIO backend includes an `alert` key in a Live Activity push payload and
the user taps the resulting banner, the OS delivers the tap through
`userNotificationCenter(_:didReceive:withCompletionHandler:)` — the same
delegate method `MessagingPushModule` monitors for standard push clicks.

Live Activity payloads are identifiable by the presence of `aps.event`
(`"update"`, `"end"`, or `"start"`), which no standard CIO push payload
contains. `MessagingPushModule`'s push event handler checks for this field and
exits early before any CIO-specific handling runs.

**Backend guidance:** Including `alert` in Live Activity pushes should be
avoided unless there is a specific UX reason. Keeping the two payload types
separate eliminates this edge case entirely.

---

## Storage

> **iOS only.** Push-to-start token deduplication is an iOS-specific concern. Android has no equivalent local storage requirement for Live Activity registration.

### Migration: `004-live-activity-schema`

```sql
CREATE TABLE IF NOT EXISTS live_activity_push_to_start (
    activity_type   TEXT    NOT NULL PRIMARY KEY,
    token_hex       TEXT    NOT NULL,
    registered_at   INTEGER NOT NULL
);
```

`activity_type` is the stable reverse-DNS `identifier` declared in `register(_:identifier:)`.

---

## Reset Behaviour

On `CIOEvent.ResetEvent`:

1. All currently-running activities of each registered type are ended via
   `activity.end(dismissalPolicy: .immediate)`.
2. All observation tasks are cancelled.
3. `live_activity_push_to_start` is truncated.
4. The `observedActivities` stream is finished.

A new `observedActivities` stream is created immediately after the old one is finished,
so the host app can re-subscribe without waiting for `configure()`. The next `configure()`
will restart observation and re-register tokens from scratch.

---

## Out of Scope (this version)

- Remote activity updates via APNs (the server uses registered instance tokens to
  push; the SDK does not initiate pushes).
- Offline queuing for failed activity update requests.
- Automatic derivation of `liveActivitiesBaseURL` from `SdkConfig.region`.
