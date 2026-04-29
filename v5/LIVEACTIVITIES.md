# Live Activities — Design Specification

**Status:** Design only — implementation not yet started
**Last updated:** March 18, 2026

---

## Overview

Live Activities (iOS 16.1+) and Live Updates (Android 16+) are the platform-native mechanisms for
displaying continuously-updating information on the Lock Screen without sending a stream of separate
push notifications. The two platforms solve the same user problem differently:

| | iOS Live Activities | Android Live Updates |
|---|---|---|
| Framework | ActivityKit | NotificationCompat (ongoing) |
| Token model | Separate per-activity push token | Existing FCM device token |
| UI | Custom widget defined by app | System-rendered notification style |
| Backend push type | APNs `apns-push-type: liveactivity` | FCM with `ongoing: true` flag |
| Push-to-start | iOS 17.2+ (push creates the activity) | Not applicable |
| SDK registration needed | Yes — per-activity token | No — device FCM token reused |

`LiveActivitiesModule` (iOS) and `LiveUpdatesModule` (Android) give the CIO backend the information
it needs to drive updates from campaigns and automations on both platforms. The SDK is responsible for:

- **iOS**: Registering per-activity push tokens (and their rotations) with the backend; registering
  push-to-start tokens (iOS 17.2+); reporting lifecycle and interaction events.
- **Android**: Reporting device capability and lifecycle/interaction events; no separate token
  registration is needed because FCM device tokens already reach the backend via the push module.

Neither module defines what an activity looks like. Widget UI and `ContentState` types belong entirely
to the host app. The SDK operates at the token and lifecycle level only.

---

## Platform Constraints

### iOS

- **iOS 16.1+** required. The module is gated `#if os(iOS)` throughout.
- **Push-to-update** is available since iOS 16.1. The backend sends an APNs payload with
  `apns-push-type: liveactivity` to the per-activity token.
- **Push-to-start** requires iOS 17.2+. A separate system-level token (per activity type, not per
  activity instance) allows the backend to create an activity without the app running.
- **Maximum 5 concurrent activities** system-enforced. Token management handles multiple simultaneous
  activities.
- **Activity lifespan.** Up to 8 hours by default, extendable to 12 with the
  `NSSupportsLiveActivitiesFrequentUpdates` entitlement. The backend must not push to tokens for
  ended activities.
- **Token rotation.** Activity push tokens change during the activity's lifetime. The SDK observes
  the token stream and re-registers on change. The backend must always use the most recently
  registered token.

### Android

- **Android 16+ (API 36)** required for Live Updates. The feature is a system-level promotion of
  ongoing notifications released in Android 16. Pre-Android-16 devices receive standard
  notifications without OS promotion; the module degrades gracefully via a runtime API-level check.
- **No separate token.** Android Live Updates are delivered via the app's existing FCM device token.
  The backend distinguishes Live Update payloads from standard notifications via message data fields.
- **System controls promotion.** Unlike iOS, the OS decides if and how prominently a notification is
  promoted based on whether the app declares the appropriate foreground service type. The SDK has no
  direct control over this.
- **Notification channels** must be configured by the host app; the SDK does not create channels.

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
│  2. Token        │         │  {activityId}         │         │                │
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
│     deregisters  │         │  {activityId}         │         │                │
│                  │──track──▶  "Live Activity Ended" │         │                │
└──────────────────┘         └──────────────────────┘         └────────────────┘
```

The SDK's role is steps 2 and 5. Steps 3 and 4 happen entirely in the backend and are out of scope
for the SDK. The SDK never sends content updates — it only manages token registration and analytics.

---

## Goals

- Accept per-activity push tokens from the app and register them with the CIO backend via a dedicated
  REST endpoint (not the event queue — registration must be synchronous and immediate).
- Track token rotation and re-register on change.
- Register push-to-start tokens (iOS 17.2+) per activity type.
- Emit analytics events for: activity started, activity ended (with reason), user tap/interaction,
  and push-to-start token registration.
- Report Android Live Update capability as a device attribute.
- Report Android Live Update lifecycle and interaction events as analytics.
- Clear all stored activity tokens and cancel all observation tasks on `ResetEvent`.
- Expose a type-erased public API that does not require the SDK to know the app's
  `ActivityAttributes` types at compile time.

---

## Non-Goals

- **Widget rendering.** The SDK has no involvement in how activities look.
- **Content state parsing.** `ContentState` payloads are the app's and backend's concern. The SDK
  passes them through opaquely.
- **Stale activity cleanup.** Deregistering ended activities from the backend registry is handled
  by the SDK's DELETE call; the backend is responsible for not pushing to stale tokens.
- **Notification channel management (Android).** The host app owns channel creation.
- **Permission prompts.** Live Activity permission on iOS and notification permission on Android are
  the app's responsibility.

---

## Configuration

### iOS

```swift
SdkConfigBuilder(cdpApiKey: "…")
    .liveActivities {
        LiveActivityConfigBuilder()
            .register(OrderAttributes.self)
            .register(DeliveryAttributes.self)   // one call per ActivityAttributes type
    }
    .build()
```

```swift
public struct LiveActivityConfigBuilder {
    /// Emit analytics events for activity lifecycle (start, end, tap). Default: true.
    public var trackLifecycleEvents: Bool = true

    /// Register push-to-start tokens automatically when detected (iOS 17.2+). Default: true.
    public var trackPushToStartTokens: Bool = true

    /// Register an ActivityAttributes type with the SDK.
    ///
    /// The SDK stores a type-erased representation of T at config time. On
    /// `resumeTracking()`, it enumerates `Activity<T>.activities` and
    /// re-registers any existing tokens, and begins observing
    /// `Activity<T>.pushToStartTokenUpdates` (iOS 17.2+).
    ///
    /// T must conform to `CIOActivityAttributes`.
    @available(iOS 16.1, *)
    public func register<T: CIOActivityAttributes>(_ type: T.Type) -> Self
}
```

Omitting `.liveActivities { … }` entirely leaves the module unregistered.

### Android

```kotlin
SdkConfigBuilder(cdpApiKey = "…")
    .liveUpdates(LiveUpdateConfig())
    .build()

data class LiveUpdateConfig(
    val trackLifecycleEvents: Boolean = true
)
```

---

## Public API

### iOS — `CIOActivityAttributes`

The app's `ActivityAttributes` types conform to this protocol to enable the declarative
registration and automatic resume API:

```swift
@available(iOS 16.1, *)
public protocol CIOActivityAttributes: ActivityAttributes {

    /// The activity type string used for backend targeting.
    /// Must be stable across app versions — campaigns reference this string.
    static var cioActivityType: String { get }

    /// A stable instance ID for this activity. Generate this before calling
    /// `Activity.request(...)` and store it in the attributes struct so the
    /// widget extension can embed it in tap `Link` URLs.
    var cioActivityId: String { get }

    /// Optional metadata sent to the backend at registration time.
    /// Default implementation returns empty — override to add fields.
    var cioMetadata: [String: Variant] { get }
}

// Default implementation — conforming types only need the two required members
@available(iOS 16.1, *)
extension CIOActivityAttributes {
    public var cioMetadata: [String: Variant] { [:] }
}
```

A minimal conforming type:

```swift
struct OrderAttributes: ActivityAttributes, CIOActivityAttributes {
    static let cioActivityType = "order_tracking"

    let cioActivityId: String       // UUID().uuidString, generated before Activity.request()
    let orderId: String
    let restaurantName: String

    var cioMetadata: [String: Variant] {
        ["order_id": .string(orderId), "restaurant_name": .string(restaurantName)]
    }

    struct ContentState: Codable, Hashable {
        var status: OrderStatus
        var estimatedMinutes: Int
        var driverName: String?
    }
}
```

### iOS — `cio.liveActivities`

```swift
/// Re-register tokens for all currently active activities and begin push-to-start
/// token observation for all registered types.
///
/// Call once from applicationDidBecomeActive (or equivalent). The SDK enumerates
/// Activity<T>.activities for each registered type, calls trackActivity(_:) for
/// each, and begins observing Activity<T>.pushToStartTokenUpdates (iOS 17.2+).
///
/// This is nonisolated — no await or Task wrapper required at the call site.
@available(iOS 16.1, *)
public nonisolated func resumeTracking()

/// Register a new activity and begin observing its push token stream.
///
/// Preferred overload for types conforming to CIOActivityAttributes. The SDK
/// extracts activityId, activityType, and metadata from the activity's attributes,
/// observes pushTokenUpdates internally, and automatically observes
/// activityStateUpdates to call activityDidEnd when the activity ends or is dismissed.
/// No manual state observation or activityDidEnd call is required.
@available(iOS 16.1, *)
public func trackActivity<T: CIOActivityAttributes>(_ activity: Activity<T>) async

/// Register a new activity using explicit parameters.
///
/// Use when ActivityAttributes does not conform to CIOActivityAttributes, or when
/// the app manages state observation itself.
@available(iOS 16.1, *)
public func trackActivity(
    tokenUpdates: AsyncStream<Data>,
    activityId: String,
    activityType: String,
    attributes: [String: Variant] = [:]
) async

/// Notify the SDK that an activity has ended.
///
/// When using the CIOActivityAttributes-conforming trackActivity(_:) overload,
/// this is called automatically — manual invocation is not required.
/// When using the explicit overload, call this when the activity ends.
@available(iOS 16.1, *)
public func activityDidEnd(
    activityId: String,
    reason: ActivityEndReason = .unknown
) async

/// Record a user interaction with a Live Activity widget.
///
/// Call from `.onOpenURL` or `scene(_:openURLContexts:)` when the URL originated
/// from a Live Activity tap. Emits a "Live Activity Tapped" analytics event.
/// Synchronous — no await or Task wrapper required.
@available(iOS 16.1, *)
public nonisolated func activityDidReceiveInteraction(activityId: String)

/// Register a push-to-start token for a given activity type (iOS 17.2+).
///
/// When types are registered via LiveActivityConfigBuilder.register(_:),
/// resumeTracking() calls this automatically. Use this method directly only
/// when managing push-to-start observation manually.
@available(iOS 17.2, *)
public func trackPushToStartToken(
    updates: AsyncStream<Data>,
    activityType: String
) async

/// Manually register a single activity token without starting the observation loop.
///
/// Use when the app manages the pushTokenUpdates loop itself.
@available(iOS 16.1, *)
public func registerActivityToken(
    _ tokenData: Data,
    activityId: String,
    activityType: String,
    attributes: [String: Variant] = [:]
) async
```

```swift
@available(iOS 16.1, *)
public enum ActivityEndReason: String, Sendable {
    case unknown        // SDK auto-detected stream end or no reason specified
    case userDismissed  // activity.activityState == .dismissed
    case expired        // activity exceeded maximum lifespan
    case programmatic   // app called Activity.end(...) explicitly
}
```

### iOS — Typical app integration

**Configuration (once):**

```swift
SdkConfigBuilder(cdpApiKey: "…")
    .liveActivities {
        LiveActivityConfigBuilder()
            .register(OrderAttributes.self)
    }
    .build()
```

**On become active (once — replaces the entire per-type resume block):**

```swift
cio.liveActivities.resumeTracking()
```

**Starting an activity:**

```swift
let activity = try Activity.request(
    attributes: OrderAttributes(
        cioActivityId: UUID().uuidString,
        orderId: orderId,
        restaurantName: restaurantName
    ),
    contentState: initialState,
    pushType: .token
)

// SDK handles token observation, rotation, and end reporting automatically
await cio.liveActivities.trackActivity(activity)
```

**Reporting taps:**

```swift
// SwiftUI
.onOpenURL { url in
    if let id = url.queryParameter("cio_activity_id") {
        cio.liveActivities.activityDidReceiveInteraction(activityId: id)
    }
}

// UIKit scene delegate
func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
    for context in urlContexts {
        if let id = context.url.queryParameter("cio_activity_id") {
            cio.liveActivities.activityDidReceiveInteraction(activityId: id)
        }
    }
}
```

The widget embeds `cioActivityId` (stored in `ActivityAttributes`) in its tap `Link` URL.
The app is responsible for embedding and parsing the URL; the SDK only requires the
`activityId` string.

**What the developer does not write:**

- Token hex encoding, storage, or rotation detection
- HTTP calls to register or deregister tokens
- `activityStateUpdates` observation or `activityDidEnd` calls (when using the
  `CIOActivityAttributes` overload)
- `Activity<T>.pushToStartTokenUpdates` observation or `trackPushToStartToken` calls
  (handled by `resumeTracking()` for registered types)
- `Task { }` wrappers for `resumeTracking()` or `activityDidReceiveInteraction`

The app is responsible for generating `cioActivityId` and including it in
`ActivityAttributes`, and for embedding it in widget `Link` URLs.

The explicit `trackActivity(tokenUpdates:activityId:activityType:attributes:)` overload
remains available as an escape hatch for types that do not conform to `CIOActivityAttributes`.

### Android — `cio.liveUpdates`

```kotlin
/**
 * Notify the SDK that a Live Update notification has been shown.
 *
 * Call when your foreground service or NotificationManager posts a Live Update-style
 * notification. The SDK emits a "Live Update Shown" analytics event and records the
 * notification as active.
 */
fun trackNotification(
    notificationId: Int,
    activityType: String,
    attributes: Map<String, Variant> = emptyMap()
)

/**
 * Notify the SDK that a Live Update notification has ended.
 */
fun notificationEnded(
    notificationId: Int,
    reason: LiveUpdateEndReason = LiveUpdateEndReason.UNKNOWN
)

/**
 * Record a user interaction with a Live Update notification (action button tap, or
 * notification tap).
 */
fun notificationInteracted(notificationId: Int, actionId: String? = null)

enum class LiveUpdateEndReason {
    UNKNOWN,
    USER_DISMISSED,
    COMPLETED,
    PROGRAMMATIC
}
```

---

## SDK → Backend Wire Format

Token registration uses direct REST calls — **not** the event queue. The backend must receive
tokens synchronously so it can push updates immediately. Failed registration calls are retried
with exponential backoff independently of the event upload pipeline.

Analytics events flow through the standard `track` event pipeline (batched, encrypted queue).

### Base URL

The base URL follows the same region routing as the rest of the SDK (`cdp.customer.io` for US,
`cdp-eu.customer.io` for EU). All endpoints below are relative to this base. The exact path
prefix (`/v1`, `/api`, etc.) is to be confirmed with the backend team.

### Authentication

Same authentication as all other SDK calls: HTTP Basic with the CDP API key as the username and
an empty password.

---

### iOS: Register / Update Per-Activity Token

```
PUT /v1/live_activities/{activityId}
Authorization: Basic {cdpApiKey}:
Content-Type: application/json

{
  "activity_type": "order_tracking",
  "token":         "a3f9…",          // hex-encoded Data
  "attributes":    { "order_id": "12345" }
}
```

The SDK calls this:
- Immediately when the first token is received from `pushTokenUpdates`.
- Again whenever the token rotates (new value from the stream).

**Response:** `200 OK` or `201 Created`. On `4xx`, log and do not retry. On `5xx` or network
error, retry with backoff (up to 3 attempts). If the activity ends before a retry succeeds, the
pending retry is cancelled.

---

### iOS: Deregister Activity (on End)

```
DELETE /v1/live_activities/{activityId}
Authorization: Basic {cdpApiKey}:
Content-Type: application/json

{
  "reason": "user_dismissed"   // "unknown" | "user_dismissed" | "expired" | "programmatic"
}
```

The SDK calls this when `activityDidEnd` is invoked or when the token stream ends naturally.
On network failure, the deletion is retried. The analytics `"Live Activity Ended"` event is
sent through the standard pipeline regardless of whether the DELETE succeeds.

---

### iOS: Register / Update Push-to-Start Token

```
PUT /v1/live_activity_push_to_start/{activityType}
Authorization: Basic {cdpApiKey}:
Content-Type: application/json

{
  "token": "b8e1…"
}
```

One endpoint per activity type the app supports. The SDK calls this when the initial token is
received and when it rotates. Push-to-start tokens are device-scoped, not profile-scoped; the
backend associates them with both the device ID and the current profile (if identified).

---

### Analytics Events (Standard Track Pipeline)

All events include the standard envelope fields (`anonymousId`, `userId`, `timestamp`,
`messageId`). Only `properties` are shown below.

**Live Activity Started** — emitted when the first token from `pushTokenUpdates` is received.

```json
{
  "event": "Live Activity Started",
  "properties": {
    "activity_id":   "abc123",
    "activity_type": "order_tracking",
    "platform":      "ios"
  }
}
```

**Live Activity Ended** — emitted when `activityDidEnd` is called.

```json
{
  "event": "Live Activity Ended",
  "properties": {
    "activity_id":   "abc123",
    "activity_type": "order_tracking",
    "reason":        "user_dismissed",
    "platform":      "ios"
  }
}
```

**Live Activity Tapped** — emitted when `activityDidReceiveInteraction` is called.

```json
{
  "event": "Live Activity Tapped",
  "properties": {
    "activity_id":   "abc123",
    "activity_type": "order_tracking",
    "platform":      "ios"
  }
}
```

**Push-to-Start Token Registered** — emitted once per activity type when the first
push-to-start token is received (not on rotation — rotation is silent to analytics).

```json
{
  "event": "Live Activity Push-to-Start Token Registered",
  "properties": {
    "activity_type": "order_tracking",
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
    "activity_type":   "order_tracking",
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
    "activity_type":   "order_tracking",
    "reason":          "completed",
    "platform":        "android"
  }
}
```

**Live Update Interacted** (Android) — emitted when `notificationInteracted` is called.

```json
{
  "event": "Live Update Interacted",
  "properties": {
    "notification_id": 1001,
    "activity_type":   "order_tracking",
    "action_id":       "view_order",
    "platform":        "android"
  }
}
```

**Live Update Unrecognized Type** (Android) — emitted when the SDK receives an FCM message
with `cio_live_update: true` and a `cio_activity_type` value that is not present in any
registered `LiveUpdateConfig`. This surfaces backend misconfiguration (wrong type string in
the campaign) without requiring the SDK to poll for validation.

```json
{
  "event": "Live Update Unrecognized Type",
  "properties": {
    "activity_type": "unknown_type",
    "platform":      "android"
  }
}
```

iOS note: The SDK has no visibility into push-to-start rejections. If `attributes-type` in
the APNs payload does not match the app's Swift type name, the OS silently rejects the
push-to-start attempt. The SDK never receives the payload and cannot emit an event. Mitigation
is documented in [Backend Behavior Suggestions](#backend-behavior-suggestions).

---

## Backend → Device Wire Format

This section is a specification for the CIO backend team. The iOS SDK has no role in these
payloads; they are sent directly from the backend to APNs or FCM.

### iOS: Push-to-Update

Sent when a campaign or automation triggers an update to an active activity.

```
APNs Headers:
  apns-push-type: liveactivity
  apns-topic:     {bundle-id}.push-type.liveactivity
  apns-priority:  5   (silent, preferred for most updates)
                  10  (alert, use sparingly — wakes the device more aggressively)

Body:
{
  "aps": {
    "timestamp":     1711750000,
    "event":         "update",
    "content-state": { ... app-defined ContentState ... },
    "alert": {                          // optional — only include for alert-priority pushes
      "title": "Order updated",
      "body":  "Your order is almost ready"
    },
    "stale-date":    1711753600         // optional — when to show stale UI
  }
}
```

`content-state` is treated as an opaque JSON object by the backend and passed through
without modification. Its structure is determined by the app's `ContentState` type and must
be agreed upon between the app developer and whoever configures the campaign.

### iOS: Push-to-End

Sent when a campaign or automation terminates the activity.

```
{
  "aps": {
    "timestamp":      1711750000,
    "event":          "end",
    "content-state":  { ... final state ... },
    "dismissal-date": 1711750300        // optional — when the OS removes the activity banner
  }
}
```

### iOS: Push-to-Start (iOS 17.2+)

Sent when a campaign creates a new activity on the device without the app running. The backend
uses the push-to-start token for the matching `activity_type`.

```
APNs Headers:
  apns-push-type: liveactivity
  apns-topic:     {bundle-id}.push-type.liveactivity

Body:
{
  "aps": {
    "timestamp":       1711750000,
    "event":           "start",
    "content-state":   { ... initial ContentState ... },
    "attributes-type": "OrderAttributes",     // must match the Swift type name exactly
    "attributes":      { ... initial ActivityAttributes values ... }
  }
}
```

`attributes-type` must match the Swift type name of the app's `ActivityAttributes` conformance.
This is a hard constraint from Apple: the string is case-sensitive and must be exact. The app
developer must communicate this string when registering the push-to-start token so the backend
can store and use it correctly.

After a successful push-to-start, the device creates the activity and begins emitting
`pushTokenUpdates`. The SDK will receive this stream (if the app forwards it) and register
the per-activity token via the standard `PUT /v1/live_activities/{activityId}` endpoint.

### Android: Live Updates (FCM)

Android Live Updates are delivered as FCM messages to the device's existing push token. The
backend uses the device's FCM token, which is already registered via the standard push module.

```json
{
  "message": {
    "token": "{fcm_device_token}",
    "android": {
      "priority": "normal",
      "notification": {
        "channel_id": "{channel_id}",    // defined by the app
        "ongoing":    true,
        "ticker":     "Order update"
      },
      "data": {
        "cio_live_update":   "true",
        "cio_activity_type": "order_tracking",
        "cio_notification_id": "1001",
        "cio_content":       "{ ... app-defined content payload as JSON string ... }"
      }
    }
  }
}
```

The `cio_content` field is an opaque JSON string that the app's notification receiver
deserialises and uses to update the notification. Its schema is defined by the app developer.
The `cio_notification_id` is a stable ID for this logical activity, used to update (rather than
create a new) notification via `NotificationManagerCompat.notify(id, …)`.

**Ending a Live Update:**

To end the notification, the backend sends a dedicated termination message:

```json
{
  "message": {
    "token": "{fcm_device_token}",
    "android": {
      "data": {
        "cio_live_update":     "true",
        "cio_action":          "end",
        "cio_notification_id": "1001",
        "cio_activity_type":   "order_tracking"
      }
    }
  }
}
```

The SDK's Android notification handler intercepts messages with `cio_live_update: true` and
`cio_action: end`, cancels the notification, and emits the `"Live Update Ended"` analytics
event automatically.

---

## Backend Service Spec

This section describes the data model and APIs the CIO backend must implement to support the
wire format above.

### Data Model

```sql
-- Per-activity tokens (iOS)
CREATE TABLE live_activity_tokens (
    workspace_id    TEXT     NOT NULL,
    device_id       TEXT     NOT NULL,
    profile_id      TEXT,                    -- NULL if anonymous at time of registration
    activity_id     TEXT     NOT NULL,
    activity_type   TEXT     NOT NULL,
    token           TEXT     NOT NULL,
    attributes_type TEXT,                    -- Swift type name; required for push-to-start reply
    attributes      JSONB,
    status          TEXT     NOT NULL DEFAULT 'active',   -- 'active' | 'ended'
    end_reason      TEXT,                    -- populated when status = 'ended'
    registered_at   TIMESTAMPTZ NOT NULL,
    token_updated_at TIMESTAMPTZ NOT NULL,
    ended_at        TIMESTAMPTZ,
    PRIMARY KEY (workspace_id, activity_id)
);

-- Push-to-start tokens (iOS 17.2+)
-- One row per (workspace, device, activity_type). Upserted on each token update.
CREATE TABLE live_activity_push_to_start_tokens (
    workspace_id     TEXT        NOT NULL,
    device_id        TEXT        NOT NULL,
    profile_id       TEXT,
    activity_type    TEXT        NOT NULL,
    token            TEXT        NOT NULL,
    registered_at    TIMESTAMPTZ NOT NULL,
    token_updated_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (workspace_id, device_id, activity_type)
);
```

### Endpoints Consumed by the SDK

These endpoints receive calls directly from the SDK and must respond quickly (< 200 ms p99).

**PUT /v1/live_activities/{activityId}**
Upserts the per-activity token record. Associates with the authenticated device and current
profile (from the Authorization header / CDP API key context). On conflict, updates `token`
and `token_updated_at`.

**DELETE /v1/live_activities/{activityId}**
Sets `status = 'ended'`, `end_reason`, and `ended_at`. Does not delete the row (retained for
analytics). Returns `200` even if the activity was already ended (idempotent).

**PUT /v1/live_activity_push_to_start/{activityType}**
Upserts the push-to-start token for the authenticated device + activity type. On conflict,
updates `token` and `token_updated_at`.

### Endpoints Consumed by Campaigns and Automations

These endpoints are called by the CIO campaign engine when a marketer or automation triggers
a Live Activity action.

**POST /api/campaigns/v1/live_activity/send**

```json
{
  "profile_id":       "prof_abc123",
  "activity_id":      "act_xyz",          // required for "update" and "end" actions
  "activity_type":    "order_tracking",   // required for "start" action
  "action":           "update",           // "start" | "update" | "end"

  // For "update" and "start":
  "content_state":    { ... },            // opaque; passed through to APNs/FCM unchanged
  "alert": {                              // optional; only for alert-priority updates
    "title": "Order updated",
    "body":  "Your order is almost ready"
  },
  "apns_priority":    5,                  // 5 (silent) or 10 (alert); default 5
  "stale_date":       1711753600,         // optional Unix timestamp

  // For "end":
  "dismissal_date":   1711750300,         // optional Unix timestamp

  // For "start" (push-to-start, iOS 17.2+):
  "attributes":       { ... },            // initial ActivityAttributes values
  "attributes_type":  "OrderAttributes"  // Swift type name; from push-to-start token record
}
```

The backend resolves the target token by looking up `live_activity_tokens` (for update/end)
or `live_activity_push_to_start_tokens` (for start) using `profile_id` + `activity_id` /
`activity_type`. If no token exists or the activity has `status = 'ended'`, the send is
a no-op and the campaign records a "not deliverable" outcome.

**For Android:** The same endpoint and `"action"` values apply. The backend determines the
platform from the device record associated with the profile. For Android devices, it uses
the FCM device token with the Live Update payload format instead of APNs.

---

## Backend Behavior Suggestions

These items are handled by the backend and do not require SDK changes, but are included
here to document expected server behavior that affects overall system correctness.

**APNs key management.** The `apns-push-type: liveactivity` push type uses the same `.p8`
key as standard `alert` pushes. The `apns-topic` suffix differs
(`{bundle-id}.push-type.liveactivity` vs `{bundle-id}`). No separate key is required, but
the backend must use the correct topic for each push type. Token storage, key rotation, and
credential hygiene are existing backend responsibilities and do not change for live activities.

**Stale token cleanup.** Tokens for ended activities (`status = 'ended'`) should not be
pushed to. When APNs returns `410 Gone` for a token, the backend should mark the corresponding
record as `status = 'ended'` and record the timestamp. Cleanup of rows older than a configurable
retention window (suggested: 30 days post-end) is a backend hygiene task.

**Token deduplication.** A PUT request with the same token value as the current record is a
no-op; `token_updated_at` should not be updated. Only update the timestamp when the token
value changes.

**Profile token ownership transfer.** Live activity tokens registered while a device is
anonymous (`profile_id = NULL`) are associated with the anonymous ID. When the SDK calls
`identify()`, the backend must reassign all live activity tokens (and push-to-start tokens)
for that device to the identified profile. This mirrors the existing behaviour for device
push tokens and ensures that activities started before login can be targeted by
profile-based campaigns.

**`attributes-type` string management (push-to-start).** The `attributes-type` field in
APNs push-to-start payloads must exactly match the Swift type name of the app's
`ActivityAttributes` conformance. This string is stored by the backend when the SDK registers
a push-to-start token. If the app renames its `ActivityAttributes` type, the stored string
becomes stale and push-to-start will silently fail. Backend operators should track this
coupling and coordinate with app developers before publishing campaigns that use push-to-start
for renamed activity types.

To reduce fragility: `cioActivityType` (the stable string the developer sets on their
`CIOActivityAttributes` conformance) is the reliable identifier for backend targeting and
campaign authoring. `attributes-type` (the Swift type name) is only needed for the APNs
push-to-start payload and should be sourced from the stored push-to-start token record, not
entered manually in campaign configuration.

---

## SDK-Side Storage

Activity tokens and metadata are stored in a `live_activity_state` table added via
`LiveActivityStorageMigration` (migration id `005-live-activity-schema`):

```sql
CREATE TABLE IF NOT EXISTS live_activity_state (
    activity_id       TEXT     NOT NULL PRIMARY KEY,
    activity_type     TEXT     NOT NULL,
    token             TEXT     NOT NULL,
    attributes        TEXT,                  -- JSON-encoded [String: Variant]
    registered_at     INTEGER  NOT NULL,
    token_updated_at  INTEGER  NOT NULL
);

-- Push-to-start tokens (iOS 17.2+)
CREATE TABLE IF NOT EXISTS live_activity_push_to_start_state (
    activity_type     TEXT     NOT NULL PRIMARY KEY,
    token             TEXT     NOT NULL,
    registered_at     INTEGER  NOT NULL,
    token_updated_at  INTEGER  NOT NULL
);
```

On `ResetEvent`, all rows in both tables are deleted and all observation tasks are cancelled.
These tables are not cleared on SDK reconfigure — activity tokens are tied to the device
installation, not the user profile.

---

## Token Observation Lifecycle (iOS)

The module maintains one internal `Task<Void, Never>` per tracked activity, and one per
registered push-to-start type. All tasks are stored in `[String: Task<Void, Never>]`
dictionaries keyed by `activityId` and `activityType` respectively.

**Per-activity task:**

1. Iterates `AsyncStream<Data>` (forwarded `pushTokenUpdates`).
2. On first token: hex-encode, store in `live_activity_state`, call
   `PUT /v1/live_activities/{activityId}`, emit `"Live Activity Started"` analytics event.
3. On subsequent tokens: hex-encode, compare to stored token, if changed call PUT again and
   update `live_activity_state`. No analytics event for rotation (token rotation is silent).
4. When stream ends naturally: call `activityDidEnd(activityId:reason:.unknown)` if not
   already called.

**Push-to-start task:**

1. Iterates `AsyncStream<Data>` (forwarded `pushToStartTokenUpdates`).
2. On first token: hex-encode, store in `live_activity_push_to_start_state`, call
   `PUT /v1/live_activity_push_to_start/{activityType}`, emit
   `"Live Activity Push-to-Start Token Registered"` analytics event.
3. On subsequent tokens: hex-encode, compare, if changed call PUT again. No analytics event.
4. Stream does not end naturally (push-to-start tokens persist for the app lifetime).

**On `ResetEvent`:**

All tasks in both dictionaries are cancelled. Both SDK-side tables are cleared.
The corresponding backend tokens are effectively orphaned (no active DELETE call is made on
reset — the backend should expire them by TTL or on next registration attempt).

---

## Platform Notes

- The entire `LiveActivitiesModule` is wrapped in `#if os(iOS)`. The `cio.liveActivities`
  accessor is unavailable at the type level on non-iOS platforms.
- `AsyncStream<Data>` is used in the explicit public API to avoid making `LiveActivitiesModule`
  generic. The SDK ships a convenience `asAsyncStream()` extension on `AsyncSequence` so the
  app does not need to write the bridging boilerplate manually.
- Push-to-start (`trackPushToStartToken`) is marked `@available(iOS 17.2, *)`. The module
  compiles on iOS 16.1+ regardless; `resumeTracking()` skips push-to-start observation on
  earlier OS versions at runtime.
- On Android, the Live Updates feature is available from Android 16 (API 36). The module
  compiles on all Android versions and degrades gracefully (no-op with a debug log) on
  pre-16 devices. The runtime guard is `Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA`
  (API 36); no feature flag is used.

---

## Push Routing and Coexistence with MessagingPush

### Why no filtering is needed

`apns-push-type: liveactivity` is a distinct APNs push type. The OS routes it
directly to the ActivityKit layer before any app or extension code runs. Specifically:

- `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` is **not called**
- `UNUserNotificationCenter` delegate methods (`willPresent`, `didReceive`) are **not called**
- The Notification Service Extension is **not invoked**

`MessagingPushModule` installs itself as the `UNUserNotificationCenter` delegate and
responds to `didReceiveRemoteNotification`. Because neither of these callbacks fires for
`liveactivity` push types, there is no intersection and no routing logic is required in
either module.

### The alert edge case

If the CIO backend includes an `alert` key in a Live Activity push payload (to show a
brief notification banner alongside the update), and the user **taps that banner**, the
OS delivers the tap through `userNotificationCenter(_:didReceive:withCompletionHandler:)` —
the same delegate method `MessagingPushModule` monitors for standard push clicks.

Live Activity payloads are identifiable by the presence of `aps.event` (`"update"`,
`"end"`, or `"start"`), which no standard CIO push payload contains.
`MessagingPushModule`'s `IOSPushEventListener` checks for this field and exits early
before any CIO-specific handling runs. See `MESSAGINGPUSH.md` → Push event handler
pipeline for the guard implementation.

**Backend guidance:** Including `alert` in Live Activity pushes should be avoided unless
there is a specific UX reason to show a banner alongside the activity update. Keeping
the two payload types separate eliminates this edge case entirely.

---

## Outstanding Work

**Prerequisites — must be resolved before implementation starts:**

- Confirm all endpoint paths and authentication scheme with the backend team. A proof-of-concept
  server will be built by the SDK team (as was done for Geofencing and Aggregation Rules) before
  backend integration begins. The Backend Behavior Suggestions section of this document is the
  working spec to hand off to the backend team when they are ready.

**iOS implementation:**

- Define `CIOActivityAttributes` protocol and `ActivityEndReason` enum.
- Define `LiveActivityConfigBuilder` with `.register<T: CIOActivityAttributes>(_:)`,
  storing type-erased `ActivityTypeRegistration` closures.
- Implement `LiveActivitiesModule` actor.
- Implement `resumeTracking()` — enumerate registered type boxes, call `trackActivity`
  for each existing activity, begin push-to-start observation for each registered type.
- Implement `trackActivity<T: CIOActivityAttributes>(_ activity: Activity<T>)` — extract
  protocol fields, call token observation machinery, and auto-observe `activityStateUpdates`
  to call `activityDidEnd` automatically.
- Implement `activityDidReceiveInteraction(activityId:)` as `nonisolated` — calls
  `root.track(...)` directly.
- Implement `LiveActivityStorageMigration` — `live_activity_state` and
  `live_activity_push_to_start_state` tables.
- Implement `StorageManager+LiveActivities.swift`.
- Ship `asAsyncStream()` convenience extension on `AsyncSequence`.
- Subscribe to `ResetEvent` → cancel all tasks, clear both storage tables.
- Add `LiveActivitiesModule` to `Package.swift`.

**Android implementation:**

- Implement `LiveUpdatesModule`.
- Handle incoming FCM messages with `cio_live_update: true` and `cio_action: end`.
- Add to Android library build.

**Documentation:**

- Define campaign-side targeting: broadcast to all active tokens of a given type for a
  profile vs. targeting by specific `activity_id`.
- Write developer integration guide and sample widget implementations for common use cases
  (delivery tracking, parking timer, sports score).

---

## Open Questions

- **Campaign targeting by type vs. by ID.** If a profile has two concurrent
  `order_tracking` activities, does the backend support fan-out to all active tokens of that
  type, or must campaigns always target a specific `activity_id`? *(Pending product decision.)*
