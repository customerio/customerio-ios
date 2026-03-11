# In-App Messaging

This document describes the Customer.io In-App Messaging subsystem. It covers initialization, the public developer interface, message types and display views, event signaling (both inbound and outbound), the message delivery lifecycle (polling and SSE), all network endpoints, the inbox API, and internal state management.

---

## 1. Key Source Files

| File | Purpose |
|------|---------|
| `Sources/MessagingInApp/MessagingInApp.swift` | Public module facade (`MessagingInApp` singleton) |
| `Sources/MessagingInApp/MessagingInAppImplementation.swift` | Internal implementation; subscribes to EventBus |
| `Sources/MessagingInApp/Type/InAppEventListener.swift` | Public callback protocol for message lifecycle events |
| `Sources/MessagingInApp/Type/InAppMessage.swift` | Public `InAppMessage` data type |
| `Sources/MessagingInApp/Config/MessagingInAppConfigBuilder.swift` | Builder for module config |
| `Sources/MessagingInApp/Gist/GistDelegate.swift` | Bridge between engine events and `InAppEventListener` + EventBus |
| `Sources/MessagingInApp/State/InAppMessageManager.swift` | Redux-style store wrapping all in-app state |
| `Sources/MessagingInApp/State/InAppMessageState.swift` | Immutable state struct |
| `Sources/MessagingInApp/State/InAppMessageAction.swift` | All dispatchable actions |
| `Sources/MessagingInApp/State/InAppMessageReducer.swift` | Pure reducer function |
| `Sources/MessagingInApp/State/InAppMessageMiddleware.swift` | Ordered middleware pipeline |
| `Sources/MessagingInApp/Gist/Network/NetworkSettings.swift` | Environment-specific API base URLs |
| `Sources/MessagingInApp/Gist/Network/GistQueueNetwork.swift` | HTTP client for Gist queue API |
| `Sources/MessagingInApp/Gist/Network/Endpoints/QueueEndpoint.swift` | Message queue endpoint |
| `Sources/MessagingInApp/Gist/Network/Endpoints/LogEndpoint.swift` | View logging and inbox endpoints |
| `Sources/MessagingInApp/Gist/Network/SSE/SseService.swift` | SSE connection wrapper (LDSwiftEventSource) |
| `Sources/MessagingInApp/Gist/Network/SSE/SseConnectionManager.swift` | SSE connection lifecycle |
| `Sources/MessagingInApp/Gist/Utilities/SseLifecycleManager.swift` | SSE start/stop based on app state |
| `Sources/MessagingInApp/Gist/Managers/QueueManager.swift` | Fetches and processes message queue |
| `Sources/MessagingInApp/Gist/Managers/MessageManager.swift` | Base class for modal/inline message rendering |
| `Sources/MessagingInApp/Gist/Managers/ModalMessageManager.swift` | Modal presentation and dismissal |
| `Sources/MessagingInApp/Gist/Managers/InlineMessageManager.swift` | Inline (embedded) message rendering |
| `Sources/MessagingInApp/Gist/Managers/LogManager.swift` | Sends view logs and inbox updates to server |
| `Sources/MessagingInApp/Gist/Managers/AnonymousMessageManager.swift` | Local caching for broadcast messages |
| `Sources/MessagingInApp/Views/UIKitInline.swift` | `InlineMessageUIView` — UIKit public view |
| `Sources/MessagingInApp/Views/SwiftUIInline.swift` | `InlineMessage` — SwiftUI public view |
| `Sources/MessagingInApp/Inbox/NotificationInbox.swift` | Public inbox protocol |
| `Sources/MessagingInApp/Inbox/DefaultNotificationInbox.swift` | Inbox implementation |
| `Sources/MessagingInApp/Inbox/Type/InboxMessage.swift` | `InboxMessage` public struct |

---

## 2. Initialization & Configuration

```swift
// Initialize the module after CustomerIO.initialize(...)
MessagingInApp
    .initialize(withConfig: MessagingInAppConfigBuilder(siteId: "your-site-id", region: .US).build())
    .setEventListener(self) // optional — register lifecycle callbacks
```

### 2a. `MessagingInAppConfigBuilder` Options

`MessagingInAppConfigBuilder` has two required parameters and no optional ones:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `siteId` | `String` | Yes | Workspace Site ID. **Separate** from the `cdpApiKey` used by `CustomerIO.initialize(...)`. Found in the Customer.io dashboard under Settings → API & Webhooks. |
| `region` | `Region` | Yes | `.US` (default) or `.EU`. Routes all Gist API requests to the correct regional endpoint. |

```swift
let config = MessagingInAppConfigBuilder(siteId: "abc123", region: .US).build()
MessagingInApp.initialize(withConfig: config)
```

**Wrapper SDK / dictionary-based initialization** (used by React Native and Flutter bridges):

```swift
// Keys: "inApp.siteId" and top-level "region"
let config = try MessagingInAppConfigBuilder.build(from: [
    "region": "EU",
    "inApp": ["siteId": "abc123"]
])
```

Throws `MessagingInAppConfigBuilderError.missingSiteId` if `siteId` is absent, or `.malformedConfig` if the `"inApp"` value is not a dictionary.

### 2b. Cross-Module Configuration (in `SDKConfigBuilder`)

These `SDKConfigBuilder` options affect in-app messaging behavior and should be set during `CustomerIO.initialize(...)`:

| Option | Type | Default | Effect on In-App |
|--------|------|---------|-----------------|
| `screenViewUse(screenView:)` | `ScreenView` | `.all` | `.all` — screen events are sent to analytics AND used for in-app route matching. `.inApp` — screen events are kept on-device only (not sent to the backend), used exclusively for in-app page-rule matching. Use `.inApp` if you want route-matched messages but don't want screen views tracked in analytics. |
| `autoTrackUIKitScreenViews(enabled:)` | `Bool` | `false` | When `true`, the SDK automatically fires a `ScreenViewedEvent` for every `UIViewController` presented. This drives automatic route matching for in-app messages in UIKit apps without manual `CustomerIO.shared.screen(...)` calls. |

```swift
CustomerIO.initialize(withConfig: SDKConfigBuilder(cdpApiKey: "...")
    .screenViewUse(screenView: .inApp)           // route matching only, no analytics tracking
    .autoTrackUIKitScreenViews(enabled: true)    // automatic UIKit route detection
    .build()
)
```

### 2c. Server-Controlled Settings

These values are **not configurable by the developer** — the server communicates them via HTTP response headers on each queue fetch:

| Response Header | State Field | Default | Description |
|----------------|-------------|---------|-------------|
| `X-Gist-Queue-Polling-Interval` | `pollInterval` | `600` seconds | How frequently the SDK polls the queue endpoint. The server may increase or decrease this based on workspace load. |
| `X-CIO-Use-SSE` | `useSse` | `false` | When `true`, the server supports real-time delivery via SSE for this workspace. SSE is used instead of polling for identified users when the app is foregrounded. |

### 2d. Initialization Side Effects

On initialization, `MessagingInAppImplementation`:
1. Dispatches `.initialize(siteId:dataCenter:environment:)` to the `InAppMessageManager` store.
2. Subscribes to EventBus events from the DataPipeline module.

---

## 3. Public Developer Interface

### 3a. `MessagingInApp` (module facade)

```swift
public class MessagingInApp: MessagingInAppInstance {
    public static var shared: MessagingInApp

    /// Register lifecycle event callbacks
    func setEventListener(_ eventListener: InAppEventListener?)

    /// Programmatically dismiss the currently displayed message
    func dismissMessage()

    /// Access inbox functionality
    var inbox: NotificationInbox
}
```

### 3b. `InAppEventListener` (callback protocol)

Implement this protocol to receive lifecycle events for in-app messages:

```swift
public protocol InAppEventListener {
    func messageShown(message: InAppMessage)
    func messageDismissed(message: InAppMessage)
    func errorWithMessage(message: InAppMessage)
    func messageActionTaken(message: InAppMessage, actionValue: String, actionName: String)
}
```

`messageActionTaken` is called for every button/link tap in a message **except** `gist://close` — the close action is treated as a dismissal rather than an actionable tap.

### 3c. `InAppMessage` (public data type)

```swift
public struct InAppMessage {
    let messageId: String      // template ID
    let deliveryId: String?    // campaignId — nil for test/preview messages
    let elementId: String?     // non-nil only for inline/embedded messages
}
```

### 3d. Inline Views

**UIKit:**
```swift
// Create and place in a UIKit view hierarchy:
let view = InlineMessageUIView(elementId: "home-banner")
view.onActionDelegate = self  // optional: InlineMessageUIViewDelegate

// Or via Storyboard:
@IBOutlet weak var inAppView: InlineMessageUIView!
inAppView.elementId = "home-banner"
```

The view self-sizes its height via Auto Layout constraints. Height is animated as content renders or changes.

**SwiftUI:**
```swift
InlineMessage(elementId: "home-banner") { message, actionValue, actionName in
    // optional: handle button taps
}
```

Both views display a loading spinner while fetching content and animate height transitions.

---

## 4. EventBus Signaling

`MessagingInAppImplementation` subscribes to four EventBus events published by the DataPipeline module:

| EventBus Event | Action Taken |
|---------------|-------------|
| `ProfileIdentifiedEvent` | `gist.setUserToken(event.identifier)` → updates `userId` in store |
| `AnonymousProfileIdentifiedEvent` | `gist.setAnonymousId(event.identifier)` → updates `anonymousId` in store |
| `ScreenViewedEvent` | `gist.setCurrentRoute(event.name)` → triggers route-based message matching |
| `ResetEvent` | `gist.resetState()` → clears userId, anonymousId, resets state |

The module also **publishes** EventBus events back to DataPipeline:

| EventBus Event Published | When |
|--------------------------|------|
| `TrackInAppMetricEvent(deliveryID:, event: "opened")` | A message becomes visible (`messageShown`) |
| `TrackInAppMetricEvent(deliveryID:, event: "clicked", params: ["actionName":, "actionValue":])` | A non-close action is tapped in a message |

`TrackInAppMetricEvent` is consumed by `DataPipelineImplementation` which calls `trackMetric()` → produces a `"Report Delivery Event"` event in the analytics pipeline.

---

## 5. Network API Endpoints

All Gist API requests use `https://consumer.inapp.customer.io` (production) as the base URL.

### Request Headers (all endpoints)

| Header | Value |
|--------|-------|
| `X-Gist-Site-ID` | Workspace Site ID |
| `X-Gist-Data-Center` | `"us"` or `"eu"` |
| `X-Gist-Client-Version` | SDK version string |
| `X-Gist-Client-Platform` | e.g. `"swift-apple"` |
| `X-Gist-User-Token` | Base64-encoded userId or anonymousId |
| `X-Gist-Is-Anonymous` | `"true"` / `"false"` |

All requests also include `sessionId` as a query parameter.

### Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/api/v4/users` | Fetch message queue for current user |
| `POST` | `/api/v1/logs/queue/{queueId}` | Log that an identified user viewed a message |
| `POST` | `/api/v1/logs/message/{messageId}` | Log that an anonymous user (or test) viewed a message |
| `PATCH` | `/api/v1/messages/{queueId}` | Update inbox message opened/unopened state |

### SSE (Server-Sent Events)

| Setting | URL |
|---------|-----|
| SSE connection | `https://realtime.inapp.customer.io/api/v3/sse` |

SSE uses the same user-token headers as the queue API. It delivers real-time message availability events, eliminating the need for polling when active.

### Engine (Message Renderer)

In-app messages are rendered as web content by a `WKWebView`:

| Setting | URL |
|---------|-----|
| Engine API | `https://engine.api.gist.build` |
| Renderer | `https://renderer.gist.build/3.0` |

---

## 6. Message Delivery: Polling vs. SSE

The SDK supports two delivery mechanisms, selected automatically based on server-negotiated capability and user identity state.

### Polling

Default mode for all users (including anonymous). The queue API (`POST /api/v4/users`) is called:
- Immediately when a user is identified.
- When the app route changes (for route-matched messages).
- After a message is dismissed (to fetch the next eligible message).
- On a timed interval (default 600 seconds, configurable via `X-Gist-Queue-Polling-Interval` response header).

HTTP 304 responses are supported — the SDK caches the last successful response body and reuses it on 304.

### SSE (Server-Sent Events)

The server signals SSE support via a response header (`X-CIO-Use-SSE`). SSE requires **all three conditions**:

1. App is foregrounded
2. [`useSse` flag is `true`] in state (set from server header)
3. User is identified (has a non-empty `userId`) — anonymous users always use polling

`CioSseLifecycleManager` manages the SSE connection:
- Starts SSE on foreground when conditions are met.
- Stops SSE when the app backgrounds.
- Restarts SSE when `useSse` flag or `userId` changes.

`SseConnectionManager` handles the actual connection with exponential backoff retry and a heartbeat timer. When SSE delivers a new-message notification, the SDK immediately fetches the message queue via `QueueManager.fetchUserQueue(...)`.

---

## 7. Message Lifecycle

### 7a. Queue Fetch → Store

```
QueueManager.fetchUserQueue(state:)
        │
        ▼
POST /api/v4/users → [InAppMessageResponse]
        │
        ▼
Convert to [Message]; separate anonymous from identified messages
        │
        ├── Anonymous messages → AnonymousMessageManager.updateMessagesLocalStore(...)
        │   └── Returns eligible anonymous messages (frequency/delay/dismiss rules; 60-min cache)
        │
        └── Identified messages + eligible anonymous messages
                │
                ▼
        dispatch(.processMessageQueue(messages:))
                │
                ▼
        State: messagesInQueue = Set<Message>
```

### 7b. Queue Processing → Display Selection

```
Action: .processMessageQueue
        │
        ▼
messageQueueProcessorMiddleware:
  - Filter already-shown messages (shownMessageQueueIds)
  - Filter messages whose page rule doesn't match currentRoute
  - Select first eligible message
        │
        ├── isEmbedded? → dispatch(.embedMessages([message]))
        │   └── State: embeddedMessagesState[elementId] = .embedded(...)
        │
        └── modal → dispatch(.loadMessage(message))
                │
                ▼
        modalMessageDisplayStateMiddleware:
          Guard: no other modal currently displayed
                │
                ▼
        dispatch(.displayMessage(message))
                │
                ▼
        Reducer: state.modalMessageState = .displayed(message)
                │
                ▼
        ModalMessageManager.onMessageDisplayed()
          └── ModalViewManager.showModalView()  [animated, .top/.center/.bottom]
```

### 7c. Rendering

Both modal and inline messages are rendered inside a `GistView` backed by a `WKWebView` (`EngineWebInstance`). The web content is fetched from `https://engine.api.gist.build` using an `EngineWebConfiguration` that includes the `siteId`, `dataCenter`, `messageId`, and optional `properties` (custom key-value data attached to the message).

The web content can call back into native via `EngineWebDelegate`:

```swift
func bootstrapped()                               // WKWebView loaded
func tap(name: String, action: String, system: Bool) // button/link tapped
func sizeChanged(message:, width:, height:)       // content size changed (inline only)
func routeChanged(newRoute:)                      // multi-page message navigation
func routeError(route:)                           // page load failure
func engineBecameVisible()
```

### 7d. Action Handling

When a message is tapped, `BaseMessageManager.tap(name:action:system:)` is called. The action string is a URL:

| Action URL | Effect |
|----------- |--------|
| `gist://close` | Dispatch `.dismissMessage(...)` |
| `gist://loadPage?url=<encoded-url>` | Open URL via `UIApplication.shared.open(url:)` |
| `gist://showMessage?messageId=<id>&properties=<base64-json>` | Dismiss current, load new message by ID |
| Any other URL | Deep link — routes through `DeepLinkUtil` (see DEEPLINKS-AND-NOTIFICATIONS.md) |

All non-close actions also fire `GistDelegate.action(...)`, which:
1. Posts `TrackInAppMetricEvent(event: "clicked")` to EventBus.
2. Calls `InAppEventListener.messageActionTaken(...)` on the host app's listener.

### 7e. View Metric Logging

When `.displayMessage` is dispatched and the message should be tracked as shown, `messageMetricsMiddleware` calls `LogManager.logView(...)`:

- **Identified user**: `POST /api/v1/logs/queue/{queueId}` — links the view to this user's delivery record.
- **Anonymous or test message**: `POST /api/v1/logs/message/{messageId}` — logs without a user context.

### 7f. Dismissal

```
Dismiss trigger:
  - User taps gist://close
  - Route changes and message has a page rule that no longer matches
  - Host app calls MessagingInApp.shared.dismissMessage()
  - Message action triggers another message load
        │
        ▼
dispatch(.dismissMessage(message:, shouldLog:, viaCloseAction:))
        │
        ▼
Reducer: state.modalMessageState = .dismissed(message)
        │
        ▼
ModalMessageManager.onMessageDismissed(messageState:)
  └── ModalViewManager.dismissModalView()  [animated]
      └── After animation: gist.fetchUserMessagesFromRemoteQueue()  [check for next message]
```

`GistDelegate.messageDismissed(message:)` is called, which forwards to `InAppEventListener.messageDismissed(message:)`.

---

## 8. Route Matching

Every in-app message can have an optional "page rule" (a route filter). When a screen view event arrives:

1. `ScreenViewedEvent` fires `gist.setCurrentRoute(event.name)` → dispatch `.setPageRoute(route:)`.
2. `routeMatchingMiddleware` checks whether the currently displayed modal still matches the new route. If not, the message is dismissed silently.
3. The message queue is re-processed against the new route, potentially loading a matching message.

Route matching is case-sensitive exact match or regex, implemented inside the `Message` type.

---

## 9. Message Types

### Modal Messages

- Displayed in a dedicated `UIWindow` on top of all other content.
- Position: `.top`, `.center`, or `.bottom` (configured in the message template).
- Animated slide-in and slide-out.
- Only one modal can be displayed at a time — a new modal is blocked if one is already active.

### Inline / Embedded Messages

- Rendered inside `InlineMessageUIView` (UIKit) or `InlineMessage` (SwiftUI).
- Identified by an `elementId` that matches the view's configured ID.
- Height auto-adjusts to content; animates height changes.
- Multiple inline messages can be displayed simultaneously (each `InlineMessageUIView` is independent).
- Do not block modal messages.

---

## 10. Anonymous (Broadcast) Messages

Anonymous messages are messages that target all users regardless of identity. They are:

- Received from the queue API mixed in with identified messages.
- Stored locally by `AnonymousMessageManager` with a 60-minute cache expiry.
- Subject to frequency rules enforced locally (max show count, delay between shows, dismiss behavior).
- Eligible anonymous messages are included in queue processing for both identified and anonymous profiles.
- Tracking (viewed/dismissed) is done locally only — no server log call is made for anonymous message metrics.

---

## 11. Inbox

The Inbox is a persistent message list for identified users. Access it via `MessagingInApp.shared.inbox`.

### `NotificationInbox` API

```swift
// Fetch current messages (optionally filtered by topic)
func getMessages(topic: String?) async -> [InboxMessage]

// Observe changes (callback-based)
@MainActor func addChangeListener(_ listener: NotificationInboxChangeListener, topic: String?)
func removeChangeListener(_ listener: NotificationInboxChangeListener)

// Observe changes (Swift Concurrency)
func messages(topic: String?) -> AsyncStream<[InboxMessage]>

// Mutations
func markMessageOpened(message: InboxMessage)
func markMessageUnopened(message: InboxMessage)
func markMessageDeleted(message: InboxMessage)
func trackMessageClicked(message: InboxMessage, actionName: String?)
```

Messages are sorted newest-first by `sentAt`. Topic filtering is case-insensitive.

### `InboxMessage` Fields

| Property | Type | Description |
|----------|------|-------------|
| `queueId` | `String` | Internal delivery queue ID |
| `deliveryId` | `String?` | Campaign delivery ID |
| `sentAt` | `Date` | Creation timestamp |
| `expiry` | `Date?` | Optional expiration |
| `topics` | `[String]` | Topic membership for filtering |
| `type` | `String` | Message type identifier |
| `opened` | `Bool` | Whether user has read the message |
| `priority` | `Int?` | Sort priority (lower = higher priority) |
| `properties` | `[String: Any]` | Custom key-value metadata |

### Inbox Server Sync

Inbox state is kept in `InAppMessageState.inboxMessages` and updated by `processInboxMessages` actions (received from the queue fetch). Open/unread state and deletions are synced to the server via:

- `PATCH /api/v1/messages/{queueId}` — mark opened/unopened
- `POST /api/v1/logs/queue/{queueId}` — mark deleted

Inbox open states are also cached locally (`InboxMessageCacheManager`) so 304-cached queue responses reflect the latest local mutations.

---

## 12. Internal State Machine

The `InAppMessageManager` is a Redux-style store (`InAppMessageStore`) built on a custom middleware pipeline. All state mutations go through this pipeline in order:

| Middleware | Role |
|-----------|------|
| `userAuthenticationMiddleware` | Blocks most actions unless userId or anonymousId is set |
| `routeMatchingMiddleware` | On route change: dismisses off-route modal; re-processes queue |
| `modalMessageDisplayStateMiddleware` | Blocks simultaneous modal loads; creates `ModalMessageManager` on main thread |
| `messageMetricsMiddleware` | Calls `LogManager.logView` on display; tracks anonymous message frequency |
| `messageQueueProcessorMiddleware` | Selects next eligible message from queue; dispatches load/embed actions |
| `inboxMessageMiddleware` | Handles inbox open/delete/click actions; calls `LogManager` for server sync |
| `messageEventCallbacksMiddleware` | Fires `GistDelegate` callbacks (`messageShown`, `messageDismissed`, `messageError`) |
| `errorReportingMiddleware` | Logs `.reportError` actions |

State is immutable; all updates return a new `InAppMessageState` via `copy(...)` or a full replacement. Subscribers receive state change notifications keyed by `KeyPath` (e.g., `\.modalMessageState`, `\.inboxMessages`).

---

## 13. Threading Model

| Component | Thread |
|-----------|--------|
| `InAppMessageManager` (store dispatch) | Any thread (store is thread-safe via `Synchronized`) |
| Reducer and middleware | Synchronous on dispatch thread |
| `modalMessageDisplayStateMiddleware` (creates `ModalMessageManager`) | Main thread (`threadUtil.runMain`) |
| `GistDelegate` callbacks (`messageShown`, etc.) | Main thread |
| `SseConnectionManager` | `actor` (cooperative thread pool) |
| `SseLifecycleManager` | `actor` |
| `DefaultNotificationInbox` listeners | Main thread (`@MainActor`) |

---

## 14. Environment URLs Summary

| Environment | Queue API | SSE API | Engine API | Renderer |
|-------------|-----------|---------|-----------|----------|
| Production | `https://consumer.inapp.customer.io` | `https://realtime.inapp.customer.io/api/v3/sse` | `https://engine.api.gist.build` | `https://renderer.gist.build/3.0` |
| Development | `https://consumer.dev.inapp.customer.io` | `https://realtime.inapp.customer.io/api/v3/sse` | `https://engine.api.dev.gist.build` | `https://renderer.gist.build/3.0` |
