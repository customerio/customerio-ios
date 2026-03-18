# Deep Link & Push Notification Handling

This document describes how the Customer.io iOS SDK handles push notifications and deep links. It covers the two integration modes, the full push-click lifecycle, foreground display, token registration, rich push via `UNNotificationServiceExtension`, and the three-tier deep link resolution strategy.

---

## 1. Key Source Files

| File | Purpose |
|------|---------|
| `Sources/MessagingPush/PushHandling/iOSPushEventListener.swift` | Primary `UNUserNotificationCenterDelegate` implementation (new architecture) |
| `Sources/MessagingPush/PushHandling/PushEventHandlerProxy.swift` | Forwards push events to all other registered delegates |
| `Sources/MessagingPush/PushHandling/PushClickHandler.swift` | Tracks push-open metrics and triggers deep link resolution |
| `Sources/MessagingPush/PushHandling/AutomaticPushClickHandling.swift` | **Deprecated** swizzle-based integration |
| `Sources/MessagingPush/PushHandling/ManualPushHandling+UserNotifications.swift` | Manual handling public API |
| `Sources/MessagingPush/PushHandling/PushEventHandler.swift` | Protocol definition for push event handlers |
| `Sources/MessagingPush/Store/PushHistory.swift` | In-memory deduplication store |
| `Sources/MessagingPush/Integration/CioProviderAgnosticAppDelegate.swift` | Base class for the new AppDelegate integration |
| `Sources/MessagingPush/MessagingPushImplementation.swift` | NSE rich push handling and metric tracking |
| `Sources/MessagingPush/RichPush/RichPushRequestHandler.swift` | Orchestrates image download for rich push |
| `Sources/MessagingPush/RichPush/RichPushDeliveryTracker.swift` | Direct HTTP delivery metric call from NSE |
| `Sources/MessagingPush/RichPush/RichPushHttpClient.swift` | HTTP client for NSE metric tracking |
| `Sources/MessagingPush/UserNotificationsFramework/Wrappers.swift` | `UNNotification*` ↔ `PushNotification` / `PushNotificationAction` adapters |
| `Sources/MessagingPush/Extensions/NotificationCenterExtensions.swift` | `didClickOnPush` / `didSwipeAwayPush` helpers |
| `Sources/MessagingPush/Type/PushNotification.swift` | `PushNotification` protocol and `PushAttachment` struct |
| `Sources/MessagingPush/Type/CustomerIOParsedPushPayload.swift` | Public `CustomerIOParsedPushPayload` typealias |
| `Sources/Common/Util/DeepLinkUtil.swift` | Three-tier deep link resolution |
| `Sources/Common/Util/UIKitWrapper.swift` | `UIApplication` / `NSUserActivity` abstraction |

---

## 2. Integration Modes

The SDK supports two integration modes. Both handle the same set of events; they differ in how the SDK becomes the `UNUserNotificationCenter.delegate`.

### 2a. New (Recommended): `CioProviderAgnosticAppDelegate`

The host application subclasses one of:

- `CioAppDelegateWrapper` — provider-agnostic base
- `CioAppDelegateAPN` — APN-specific subclass
- `CioAppDelegateFCM` — FCM-specific subclass

No swizzling is required. On `didFinishLaunchingWithOptions`:

1. The SDK saves the existing `UNUserNotificationCenter.current().delegate` as `wrappedNotificationCenterDelegate`.
2. It sets `UNUserNotificationCenter.current().delegate = self` (the `CioProviderAgnosticAppDelegate` subclass), making the SDK the sole delegate.
3. If `autoFetchDeviceToken` is enabled, it calls `UIApplication.registerForRemoteNotifications()`.

Any existing delegate is preserved and forwarded to via `PushEventHandlerProxy`.

### 2b. Deprecated: Swizzle-Based (`AutomaticPushClickHandling`)

`AutomaticPushClickHandlingImpl` swizzles the `delegate` setter on `UNUserNotificationCenter`. Any time the host app or a third-party SDK sets a new delegate, the SDK transparently intercepts the call, stores the original delegate in `PushEventHandlerProxy`, and keeps itself as the permanent delegate.

This approach is still functional for apps that have not yet adopted `CioAppDelegateWrapper`, but is deprecated because swizzling can conflict with other SDKs (e.g., Firebase) and reduces predictability.

---

## 3. Push Notification Data Model

Push payload parsing is handled by `UNNotificationWrapper` (publicly aliased as `CustomerIOParsedPushPayload`). Key extracted fields:

| Property | Payload Key | Description |
|----------|------------|-------------|
| `isPushSentFromCio` | `CIO-Delivery-ID` present | Gate for CIO-specific handling |
| `cioDelivery` | `CIO-Delivery-ID`, `CIO-Delivery-Token` | Delivery ID and device token for metric tracking |
| `cioDeepLink` | `link` (inside `"CIO"` dict) | Target URL to open after click |
| `cioImage` | `rich_notification.media.url` | Remote image URL for rich push |
| `cioAttachments` | `UNNotificationContent.attachments` | Locally cached attachment files |
| `deliveryDate` | `UNNotification.date` | Timestamp used for deduplication |
| `pushId` | `UNNotificationRequest.identifier` | Notification identifier |

Push action type is determined by `UNNotificationResponse.actionIdentifier`:

```swift
var didClickOnPush: Bool   { actionIdentifier == UNNotificationDefaultActionIdentifier }
var didSwipeAwayPush: Bool { actionIdentifier == UNNotificationDismissActionIdentifier }
```

---

## 4. Push Click Lifecycle (`onPushAction` / `didReceive`)

When the user interacts with a push notification, `iOSPushEventListener.onPushAction` is invoked:

```
OS delivers UNNotificationResponse
        │
        ▼
1. Guard: push.deliveryDate must be present
   └── missing → exit without calling completionHandler
        │
        ▼
2. Deduplication: PushHistory.hasHandledPush(pushEvent: .didReceive, pushId:, pushDeliveryDate:)
   └── already handled → skip (no double-processing)
        │
        ▼
3. Is this a CIO push? (isPushSentFromCio)
   ├── No → forward to PushEventHandlerProxy → call completionHandler → return
   └── Yes → continue
        │
        ▼
4. cleanupAfterPushInteractedWith(for:)
   └── Deletes locally cached rich push attachment files from disk
        │
        ▼
5. Did user click (not swipe away)?
   └── Yes → PushClickHandler.trackPushMetrics(for:)
               ├── guards on cioDelivery presence
               └── messagingPush.trackMetric(deliveryID:, event: .opened, deviceToken:)
                   └── fires TrackMetricEvent on EventBus
                       └── DataPipeline tracks "Report Delivery Event" {metric: "opened"}
        │
        ▼
6. PushEventHandlerProxy.onPushAction(...)
   └── @MainActor, serially awaits each registered UNUserNotificationCenterDelegate
       using withCheckedContinuation (robust to double-completion-handler calls)
        │
        ▼
7. After proxy completes — did user click?
   └── Yes → PushClickHandler.handleDeepLink(for:)
               └── guards on push.cioDeepLink?.url
                   └── DeepLinkUtil.handleDeepLink(url) [see §6]
        │
        ▼
8. completionHandler()   ← signals OS that processing is complete
```

**Why is deep link deferred to step 7?**
Opening a deep link causes the app to foreground or navigate immediately. Deferring ensures all SDK and third-party delegate processing completes before the UI transition, preventing race conditions.

---

## 5. Foreground Push Display (`shouldDisplayPushAppInForeground` / `willPresent`)

When a push arrives while the app is in the foreground, `iOSPushEventListener.shouldDisplayPushAppInForeground` is called:

```
OS delivers UNNotification (app in foreground)
        │
        ▼
1. Deduplication: PushHistory.hasHandledPush(pushEvent: .willPresent, ...)
        │
        ▼
2. Is this a CIO push?
   ├── No → forward to PushEventHandlerProxy → call completionHandler with proxy result
   └── Yes →
       ├── Read moduleConfig.showPushAppInForeground
       ├── Forward to PushEventHandlerProxy (proxy result ignored for CIO push)
       └── Call completionHandler with SDK config value
```

`CioProviderAgnosticAppDelegate` translates the boolean into `UNNotificationPresentationOptions`:

```swift
// showPushAppInForeground == true
completionHandler([.list, .banner, .badge, .sound])

// showPushAppInForeground == false
completionHandler([])
```

---

## 6. Deep Link Resolution (`DeepLinkUtil`)

`DeepLinkUtilImpl.handleDeepLink(_:)` applies a three-tier strategy in order:

```
URL received
    │
    ▼
Tier 1: deepLinkCallback registered?
    ├── Yes → call deepLinkCallback(url)
    │       ├── returns true  → handled; stop ✓
    │       └── returns false → continue to Tier 2
    └── No → continue to Tier 2
    │
    ▼
Tier 2: UIKitWrapper.continueNSUserActivity(webpageURL: url)
    ├── Calls application(_:continue:restorationHandler:) on the host app
    ├── Only works for http/https URLs (NSUserActivity.webpageURL constraint)
    ├── host app returns true  → handled; stop ✓
    └── host app returns false → continue to Tier 3
    │
    ▼
Tier 3: UIKitWrapper.open(url: url)
    └── UIApplication.shared.open(url:) — system call (browser, app scheme, etc.) ✓
```

**Notes:**
- `deepLinkCallback` is registered via `@_spi(Internal) setDeepLinkCallback(_:)` — used by React Native and Flutter wrappers. Not intended for direct host app use.
- `NSUserActivity.webpageURL` only accepts `http`/`https` schemes. App-scheme URLs (e.g. `myapp://`) skip Tier 2 and fall through to `UIApplication.open()`.
- SDK logs a message at each tier indicating how the deep link was handled (or if no tier handled it).

---

## 7. Push Event Deduplication (`PushHistory`)

`PushHistoryImpl` provides an in-memory, thread-safe deduplication store using `@Atomic`:

```swift
// Key: (pushId, pushDeliveryDate)
// Value: Set<PushHistoryEvent>  (.didReceive | .willPresent)
private var history: [String: Set<PushHistoryEvent>] = [:]
```

The composite key `pushId + deliveryDate` prevents false duplicates from local notifications, which may share the same `pushId` across multiple deliveries.

The store is never persisted to disk; it only prevents double-handling within a single app session (e.g., multiple delegates receiving the same event).

---

## 8. Multi-SDK Delegate Forwarding (`PushEventHandlerProxy`)

`PushEventHandlerProxyImpl` stores all `UNUserNotificationCenterDelegate` instances registered by third-party SDKs (wrapped as `PushEventHandler`). When the CIO handler processes an event, it forwards to all registered delegates:

- Runs on `@MainActor` for thread safety.
- Awaits each delegate's completion handler sequentially using `withCheckedContinuation`.
- Handles buggy SDKs that call the completion handler more than once (e.g., rn-firebase) by ignoring subsequent calls via a `didCallCompletionHandler` flag.

---

## 9. Push Token Registration

Token lifecycle is handled by `CioProviderAgnosticAppDelegate`:

| Callback | SDK Action | Result |
|----------|-----------|--------|
| `didRegisterForRemoteNotificationsWithDeviceToken(_:)` | `MessagingPushImplementation.registerDeviceToken(_:)` → fires `RegisterDeviceTokenEvent` on EventBus | DataPipeline calls `addDeviceAttributes(token:)` → tracks `"Device Created or Updated"` event |
| `didFailToRegisterForRemoteNotificationsWithError(_:)` | `messagingPush.deleteDeviceToken()` → fires `DeleteDeviceTokenEvent` on EventBus | DataPipeline removes device token from profile |

Token registration with the OS is triggered by calling `UIApplication.registerForRemoteNotifications()`, which happens automatically in `didFinishLaunchingWithOptions` when `autoFetchDeviceToken` is enabled.

---

## 10. Rich Push (Notification Service Extension)

Rich push (image attachments in push notifications) is handled entirely inside a host app's `UNNotificationServiceExtension`. The main app process is **not running** in this context.

### Lifecycle

```
NSE receives UNNotificationServiceExtension.didReceive(_:withContentHandler:)
        │
        ▼
MessagingPush.shared.didReceive(request, withContentHandler:)
        │
        ▼
1. Parse push via UNNotificationWrapper
   └── Not a CIO push → return false; NSE handles content itself
        │
        ▼
2. autoTrackPushEvents enabled?
   └── Yes → trackMetricFromNSE(deliveryID:event:.delivered:deviceToken:)
               └── RichPushDeliveryTrackerImpl.trackMetric(...)
                   └── POST <apiHost>/track  (direct HTTP — no EventBus)
        │
        ▼
3. RichPushRequestHandler.shared.startRequest(push:)
   ├── Downloads image from push.cioImage.url via SDK's httpClient
   ├── Saves file to a local temp URL
   └── On completion → completionHandler(modifiedContent)
                       (content now has UNNotificationAttachment with local file URL)
        │
        ▼
4. serviceExtensionTimeWillExpire() called by OS (time budget exceeded)?
   └── RichPushRequestHandler.shared.stopAll()
       └── Calls completionHandler immediately with whatever content is available
```

### Why direct HTTP (not EventBus) for NSE metrics?

The EventBus and DataPipeline live in the main application process. When iOS invokes a Notification Service Extension, the main app is **not running**, so the EventBus cannot be used. `RichPushDeliveryTrackerImpl` makes a direct HTTP call to `POST <apiHost>/track` instead.

The image attachment file written by the NSE is cleaned up during the push click lifecycle by `PushClickHandler.cleanupAfterPushInteractedWith(for:)`.

---

## 11. Metric Tracking Endpoints

| Context | Path | Notes |
|---------|------|-------|
| Push opened (in-app) | EventBus → DataPipeline → `POST https://cdp.customer.io/v1/b` | Batched with other events |
| Push delivered (NSE) | `POST https://track.customer.io/track` | Direct HTTP, no batching |

The delivery tracking endpoint base URL is determined by `RichPushHttpClient.getDefaultApiHost(region:)`:
- US: `https://track.customer.io`
- EU: `https://track-eu.customer.io`

---

## 12. Manual Handling API

Apps that do not subclass `CioProviderAgnosticAppDelegate` can forward push events manually using the extensions on `MessagingPush`:

```swift
// In your UNUserNotificationCenterDelegate:
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
) {
    let handled = MessagingPush.shared.userNotificationCenter(
        center,
        didReceive: response,
        withCompletionHandler: completionHandler
    )
    if !handled {
        completionHandler()
    }
}
```

`MessagingPush.shared.userNotificationCenter(center:didReceive:)` (without `completionHandler`) returns a `Bool` indicating whether the SDK handled the push. The host app is responsible for calling `completionHandler()` afterward.
