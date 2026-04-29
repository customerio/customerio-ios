# Feature Spec — In-App Messaging

---

## Overview

The `CustomerIO_MessagingInApp` module delivers in-app messages to identified
and anonymous users. Messages are fetched from the Gist queue service via
HTTP polling or real-time SSE, evaluated against route rules and frequency
constraints, then rendered in a WKWebView overlay (modal) or embedded directly
in the host app's layout (embedded/inline). A persistent inbox provides
access to longer-lived messages outside the normal display queue.

See also: ADR 010 (Swift 6 concurrency migration).

---

## Configuration

```swift
SdkConfigBuilder(cdpApiKey: "…")
    .inApp {
        MessagingInAppConfigBuilder(siteId: "YOUR_SITE_ID")
    }
    .build()
```

`siteId` is a required string issued by the Customer.io dashboard. No other
configuration options exist for this module; delivery parameters (polling
interval, SSE enablement) are supplied at runtime by the server via response
headers.

Module accessed at runtime via `cio.inApp`.

---

## Public API

### `MessagingInAppModule`

The module exposes two capabilities to host apps:

- **`setEventListener(_ listener: (any InAppEventListener)?)`** — registers
  a lifecycle delegate that receives callbacks when messages are shown,
  dismissed, fail to load, or produce a user action.
- **`inbox: any NotificationInbox`** — returns the inbox instance for
  persistent message management.

### `InAppEventListener`

```swift
public protocol InAppEventListener: AnyObject {
    func messageShown(message: InAppMessage)
    func messageDismissed(message: InAppMessage)
    func errorWithMessage(message: InAppMessage)
    func messageActionTaken(message: InAppMessage, actionValue: String, actionName: String)
}
```

Callbacks fire on a background thread; host apps that update UI must dispatch
to the main thread themselves. `InAppEventListener` conforming types are not
required to be `Sendable` (see ADR 010).

### `InAppMessage`

Public representation of a message, passed to `InAppEventListener` callbacks:

```swift
public struct InAppMessage: Sendable, Equatable {
    public let messageId: String       // Template/message identifier
    public let deliveryId: String?     // Campaign/delivery identifier (for analytics)
    public let elementId: String?      // Nil for modal, non-nil for embedded
}
```

### `NotificationInbox`

```swift
public protocol NotificationInbox: Sendable {
    func getMessages(topic: String?) async -> [InboxMessage]
    @MainActor func addChangeListener(_ listener: NotificationInboxChangeListener, topic: String?)
    func removeChangeListener(_ listener: NotificationInboxChangeListener)
    func markMessageOpened(message: InboxMessage)
    func markMessageUnopened(message: InboxMessage)
    func markMessageDeleted(message: InboxMessage)
    func trackMessageClicked(message: InboxMessage, actionName: String?)
    func messages(topic: String?) -> AsyncStream<[InboxMessage]>
}
```

- `topic` filtering is case-insensitive; `nil` returns all messages.
- Messages are sorted by `sentAt` descending (newest first).
- `messages(topic:)` emits the current list immediately on subscription then
  again on every subsequent change. Prefer this over `addChangeListener` in
  new code.
- `getMessages(topic:)` returns the current snapshot from state without a
  network fetch.

### `NotificationInboxChangeListener`

```swift
@MainActor public protocol NotificationInboxChangeListener: AnyObject {
    func onMessagesChanged(messages: [InboxMessage])
}
```

Guaranteed to fire on the main thread. Host apps may update UI directly inside
`onMessagesChanged`.

### `InboxMessage`

```swift
public struct InboxMessage: Equatable, @unchecked Sendable {
    public let queueId: String
    public let deliveryId: String?
    public let expiry: Date?
    public let sentAt: Date
    public let topics: [String]
    public let type: String
    public let opened: Bool
    public let priority: Int?
    public let properties: [String: Any]
}
```

All properties are immutable. `@unchecked Sendable` because `properties:
[String: Any]` is not natively `Sendable`; it is safe because `properties`
is assigned at init and never mutated.

---

## State Machine

All module state lives in a single `InAppMessageState` value, managed by an
actor-isolated Redux-style store.

### `InAppMessageState`

| Field | Type | Default | Description |
|---|---|---|---|
| `siteId` | String | "" | Customer.io site identifier |
| `dataCenter` | String | "" | Server region (e.g. "US", "EU") |
| `environment` | GistEnvironment | `.production` | API environment |
| `cdnHost` | URL? | nil | Custom renderer base URL |
| `pollInterval` | Double | 600 | Polling interval in seconds |
| `useSse` | Bool | false | Server-signalled SSE preference |
| `sseUsable` | Bool | true | Client-side SSE viability |
| `userId` | String? | nil | Identified user token |
| `anonymousId` | String? | nil | Anonymous session identifier |
| `currentRoute` | String? | nil | Current screen/route |
| `modalMessageState` | ModalMessageState | `.initial` | Active modal lifecycle |
| `embeddedMessagesState` | EmbeddedMessagesState | empty | Per-elementId embedded state |
| `messagesInQueue` | Set\<Message\> | [] | Pending display queue |
| `inboxMessages` | [InboxMessage] | [] | Persistent inbox |
| `shownMessageQueueIds` | Set\<String\> | [] | Dedup set for shown messages |

**Computed:**
- `isUserIdentified` — `userId != nil && !userId.isEmpty`
- `shouldUseSse` — `useSse && isUserIdentified && sseUsable`
- `effectiveRendererBaseURL` — `cdnHost` if set, otherwise environment default

### `ModalMessageState`

```
.initial → .loading(message) → .displayed(message) → .dismissed(message)
```

State transitions are one-directional within a session; a new message starts
the sequence again from `.loading`.

### `InlineMessageState`

```
.readyToEmbed(message, elementId) → .embedded(message, elementId) → .dismissed(message)
```

Unlike modal messages, embedded messages wait in `.readyToEmbed` until the host
app's `GistView` reports it is ready.

### Actions

| Action | Effect |
|---|---|
| `.initialize(siteId:dataCenter:environment:)` | Reset state; preserve identity fields |
| `.setPollingInterval(interval:)` | Update poll cadence |
| `.setSseEnabled(enabled:)` | Record server SSE preference |
| `.setSseUsable(usable:)` | Record client SSE viability (resets on foreground / user change) |
| `.setUserIdentifier(user:)` | Set userId; reset `sseUsable` to `true` |
| `.setAnonymousIdentifier(anonymousId:)` | Set anonymousId |
| `.setPageRoute(route:)` | Update current route for rule matching |
| `.processMessageQueue(messages:)` | Replace pending queue |
| `.clearMessageQueue` | Empty pending queue (e.g. no-content response) |
| `.loadMessage(message:)` | Begin loading a modal message |
| `.embedMessages(messages:)` | Register messages with elementId for embedding |
| `.displayMessage(message:)` | Mark message as displayed; add to shownIds if non-persistent |
| `.dismissMessage(message:shouldLog:viaCloseAction:)` | Mark dismissed; conditionally add to shownIds |
| `.engineAction(.tap(...))` | No state change; triggers side effects |
| `.engineAction(.messageLoadingFailed(message:))` | Transition modal to `.dismissed` |
| `.inboxAction(.updateOpened(...))` | Flip `opened` on matching inbox message |
| `.inboxAction(.deleteMessage(...))` | Remove message from inbox |
| `.inboxAction(.trackClicked(...))` | No state change; triggers analytics side effect |
| `.reportError(message:)` | No state change; used for logging |
| `.resetState` | Clear user data; preserve siteId/dataCenter/environment |

### Shown Message Tracking

A message is added to `shownMessageQueueIds` on **display** unless it is
persistent. A persistent message is added to `shownMessageQueueIds` on
**dismissal**, and only if `shouldLog: true` and `viaCloseAction: true`. This
allows persistent messages to re-appear after route changes or app restarts
until the user explicitly closes them.

---

## Message Delivery: Polling vs SSE

The SDK supports two delivery modes. The active mode is determined by the
computed property `shouldUseSse`:

```
shouldUseSse = state.useSse && state.isUserIdentified && state.sseUsable
```

### Polling

Polling is active when `shouldUseSse == false`. This includes:
- Anonymous users (regardless of `useSse`)
- `useSse` is `false` (server has not enabled SSE)
- `sseUsable` is `false` (SSE previously failed; waiting for foreground/user reset)

**Endpoint:** `POST /api/v4/users` (QueueEndpoint.getUserQueue)

**Request Headers:**
- `X-Gist-Site-Id`, `X-Gist-Data-Center`, `X-Gist-Client-Platform`, `X-Gist-Client-Version`
- `If-None-Match` (ETag for 304 caching)
- `X-Gist-User-Token` (userId or anonymousId)

**Response Headers consumed:**
- `x-gist-queue-polling-interval` — updates `pollInterval` in state (dispatches `setPollingInterval`)
- `x-cio-use-sse` — signals SSE eligibility (dispatches `setSseEnabled`)

**Response Codes:**
- `200` — new messages; dispatch `processMessageQueue` and/or `processInboxMessages`
- `304` — no changes; dispatch `clearMessageQueue`; apply cached inbox "opened" state

The polling task runs on a repeating `Task` with `Task.sleep`. It is cancelled
and replaced whenever polling parameters change. The task skips fetches when
the app is in the background.

### SSE (Server-Sent Events)

SSE is active when `shouldUseSse == true`. SSE is not used for anonymous users.

#### Connection lifecycle

1. `SseConnectionManager.startConnection()` is called (idempotent; concurrent
   calls are ignored via generation ID guard).
2. Generation ID incremented; prior connection stopped.
3. `SseService.connect(state:connectionId:)` opens an `EventSource` to the
   SSE endpoint with query params: `siteId`, `sessionId`, `userToken` (base64).
4. Connection events:
   - `.open` / `CONNECTED` server event → connection confirmed; reset retry count; start heartbeat timer
   - `heartbeat` → reset heartbeat timer; interval may be updated from event payload
   - `messages` → parse JSON; dispatch `processMessageQueue`
   - `inbox_messages` → parse JSON; dispatch `processInboxMessages`
   - `ttl_exceeded` → reconnect (TTL is a server-controlled session limit)
5. Connection closed or timed out → retry logic evaluates retry decision.

#### Heartbeat monitoring

A heartbeat timer runs while SSE is connected. Default timeout: 30 seconds plus
a 5-second buffer (35 seconds total). If no heartbeat is received within the
timeout, the connection is treated as failed and retry logic fires.

The heartbeat interval can be updated dynamically from the `heartbeat` event
payload. Maximum timeout is capped at 1 hour to prevent nanosecond overflow.

#### Retry logic

`SseRetryHelper` classifies failures:

| Condition | Decision |
|---|---|
| Network error (DNS, no route, etc.) | Retry |
| Timeout | Retry |
| HTTP 408, 429 | Retry |
| HTTP 5xx | Retry |
| HTTP 4xx (except 408, 429) | No retry (permanent failure) |

Retry schedule:
- Attempt 1: immediate
- Attempts 2–3: 5-second delay
- Maximum 3 retry attempts total

If all retries are exhausted or a non-retryable error is received,
`SseConnectionManager` dispatches `setSseUsable(usable: false)`. This prevents
the SSE/poll feedback loop: `useSse` remains `true` (server preference
unchanged), but `shouldUseSse` becomes `false`, so the SDK falls back to
polling without triggering another SSE start attempt.

`sseUsable` resets to `true` on:
- App foregrounding (via `SseLifecycleManager.handleForegrounded`)
- User identifier change (via reducer: `.setUserIdentifier` always sets `sseUsable: true`)

#### Generation IDs

Both `SseConnectionManager` and `SseService` carry a monotonically increasing
`UInt64` generation ID on every connection. Any callback, retry, or timeout
handler that carries a stale generation ID is silently discarded. This prevents
race conditions when a new connection is started before an old one has fully
torn down.

#### App lifecycle

`CioSseLifecycleManager` (UIKit only) observes `UIApplication.willEnterForegroundNotification`
and `UIApplication.didEnterBackgroundNotification`:

- **Foreground**: Reset `sseUsable` if it was `false`; start SSE if eligible.
- **Background**: Stop SSE connection unconditionally. Polling is also suspended
  in `fetchUserMessages` (checks `UIApplication.shared.applicationState`).

---

## Message Display

### Modal Messages

Modal messages render as a full-screen or positioned overlay on the key window.

**Display flow:**
1. Queue manager dispatches `processMessageQueue(messages:)`.
2. `InAppMessageMiddleware` (side effect on store) selects the next eligible
   message: not in `shownMessageQueueIds`, route rule matches `currentRoute`.
3. Dispatches `loadMessage(message:)`.
4. `ModalMessageManager` creates a `ModalViewManager` and calls
   `EngineWeb.setup(engineWebConfiguration:)` to load the message HTML.
5. On load success, dispatches `displayMessage(message:)`.
6. `ModalViewManager` presents the overlay.

**Position:** Controlled by `GistProperties.position` (`.top`, `.center`,
`.bottom`). Default is `.center`.

**Overlay color:** Optional hex string from `GistProperties.overlayColor`.

### Embedded (Inline) Messages

Embedded messages render inside a `GistView` placed by the host app.

**Display flow:**
1. Queue manager dispatches `embedMessages(messages:)`.
2. State updates `embeddedMessagesState` with `InlineMessageState.readyToEmbed`.
3. Host app registers a `GistView` (a `UIView` subclass wrapping `EngineWeb`)
   with the matching `elementId`.
4. `InlineMessageManager` detects the `readyToEmbed` state and begins loading.
5. On load success, dispatches `displayMessage(message:)` → state becomes
   `.embedded`.
6. When the host app removes the `GistView` from its superview, the view's
   delegate fires `gistViewWillRemoveFromSuperview` → auto-dismiss.

The host app creates a `GistView` via `gistInlineMessageUIViewFactory` and is
responsible for its layout.

### Route Rules

Messages may carry a route rule (`GistProperties.routeRuleApple`) that restricts
display to matching routes. Rule formats:

| Rule type | Pattern |
|---|---|
| Contains | `^(.*home.*)$` |
| Equals | `^(home)$` |
| Multiple | `^(home\|dashboard)$` |

Rules are evaluated with `NSRegularExpression`. An invalid regex is treated as
no match (message not shown). A message with no route rule matches any route.

### Action Handling

In-message actions are triggered by user interaction with buttons or links in
the rendered HTML. The EngineWeb delegate receives a `tap(name:action:system:)`
callback. Actions are routed by URL scheme:

| URL | Behavior |
|---|---|
| `gist://close` | Dismiss current message |
| `gist://loadPage?url=<url>` | Open URL in Safari or in-app browser |
| `gist://showMessage?messageId=<id>` | Load a different message by ID |
| `https://…` / `http://…` | System open (Safari) or deep link |
| Other | Passed to `InAppEventListener.messageActionTaken` |

All actions dispatch `engineAction(.tap(...))` to state (no state change) and
call the registered `InAppEventListener`.

### Persistent Messages

A message is persistent if `GistProperties.persistent == true`. Persistent
messages:
- Are **not** added to `shownMessageQueueIds` on display.
- Are added to `shownMessageQueueIds` only when dismissed via close button
  (`viaCloseAction: true`) and `shouldLog: true`.
- Can re-appear on subsequent queue fetches until explicitly closed.

Persistent messages are rare and intended for critical content that must not
be dismissed by accident.

---

## Broadcast (Anonymous) Messages

Broadcast messages are delivered to users who have not yet been identified
(anonymous users). They are marked with a non-nil `GistProperties.broadcast`
property.

**Frequency control** (enforced locally by `AnonymousMessageManager`):

| Field | Meaning |
|---|---|
| `count` | Maximum number of times to show (0 = unlimited) |
| `delay` | Seconds to wait between shows |
| `ignoreDismiss` | If true, dismissal does not count against `count` |

Broadcast messages are cached locally with a 60-minute expiry. Frequency
tracking (show count, last-shown timestamp, dismiss status) is stored per
`queueId`. They are merged with regular messages after server response
processing.

Broadcast messages are never eligible for SSE (only polling).

---

## Inbox

The inbox stores persistent messages that users can retrieve and interact with
on demand, independent of the normal display queue.

### Delivery

Inbox messages arrive alongside modal/embedded messages in poll or SSE
responses and are dispatched via `processInboxMessages(messages:)`.

### State

`InAppMessageState.inboxMessages` holds a `[InboxMessage]` array, sorted by
`sentAt` descending. Ordering and deduplication are applied before dispatch
(in `QueueManager`).

### Local Opened State

The server does not immediately reflect local `opened` changes (mark
opened/unopened). `InboxMessageCacheManager` records the user's local changes
under each `queueId`. On 304 (cached) responses the cached "opened" status
overrides the server's value, preserving the user's interaction state across
refreshes.

### Mutations

All mutations dispatch `inboxAction` sub-actions:

| Mutation | Action | Side Effect |
|---|---|---|
| `markMessageOpened` | `inboxAction(.updateOpened(message, opened: true))` | None |
| `markMessageUnopened` | `inboxAction(.updateOpened(message, opened: false))` | None |
| `markMessageDeleted` | `inboxAction(.deleteMessage(message))` | None |
| `trackMessageClicked` | `inboxAction(.trackClicked(message, actionName))` | Reports delivery event |

Analytics tracking for `trackMessageClicked` fires via a side effect registered
on `DefaultInAppMessageManager`. The side effect calls a `trackMetric` closure
that submits a `"Report Delivery Event"` track call via the parent SDK, using
the message's `campaignId` (delivery ID) as the metric payload.

---

## SDK Integration

### Initialization

`MessagingInAppModule.configure` is called automatically when the host app
calls `SdkConfigBuilder.build()`. If no `inAppConfig` is provided, the module
registers as a no-op and `cio.inApp.inbox` returns `NoOpNotificationInbox`.

On configure, the module:
1. Initializes state with `siteId`, `dataCenter`, and renderer base URL.
2. Creates the store, manager, queue manager, SSE components, and inbox.
3. Creates the `Gist` orchestrator (UIKit only).
4. Registers event-bus observers.

### User Identification

| SDK Event | Module Action |
|---|---|
| `ProfileIdentifiedEvent` | `gist.setUserToken(profileId)` → `setUserIdentifier(user:)` |
| `AnonymousProfileIdentifiedEvent` | `gist.setAnonymousId(anonymousId)` → `setAnonymousIdentifier(anonymousId:)` |
| `ResetEvent` | `gist.resetState()` → `resetState` |

On `setUserIdentifier`, the reducer also resets `sseUsable: true` so SSE is
retried for the new identity even if a prior identity had exhausted SSE retries.

### Screen Tracking

`ScreenViewedEvent` from the SDK event-bus triggers `gist.setCurrentRoute(routeName)`,
which dispatches `setPageRoute(route:)`. Route rule matching for pending
messages runs after each route change.

---

## Platform Support

All display logic (modal overlay, embedded view, SSE lifecycle) is gated on
`#if canImport(UIKit)`. On macOS or other non-UIKit platforms:

- `Gist` actor is not created; message display is a no-op.
- `NoOpSseLifecycleManager` is used; no SSE connections are opened.
- `NoOpNotificationInbox` is returned for `cio.inApp.inbox`.
- Polling does not run.

The state machine, reducer, and `InAppMessageManager` are platform-agnostic.

---

## No-Op Behaviour

When the module is not configured (`inAppConfig == nil`), all public API calls
are silent no-ops:

- `setEventListener` — ignored
- `inbox.getMessages(topic:)` — returns `[]`
- `inbox.addChangeListener` — no-op; listener never fires
- `inbox.messages(topic:)` — returns a stream that never emits
- All `inbox.mark*` and `trackMessageClicked` — ignored
