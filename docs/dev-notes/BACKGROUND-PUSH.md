# Silent (Background) Push

A silent push wakes the app in the background and hands it data. Nothing is shown to the person, and Opened never applies. This note covers what an app needs and how the SDK handles it.

---

## 1. Minimum version

Silent push needs customerio-ios **5.2.0** or later, the first release with `MessagingPush.handleBackgroundPush(userInfo:)`.

Customer.io sends silent pushes to every iOS device and doesn't check the SDK version. On an older SDK, nothing records Delivered and nothing reads the data; an app handler that exists sees an unknown push.

---

## 2. App setup

1. In Xcode, add **Background Modes → Remote notifications**. Info.plist `UIBackgroundModes` then lists `remote-notification`. Without it, iOS doesn't wake the app for a silent push.
2. Initialize MessagingPush in `application(_:didFinishLaunchingWithOptions:)` on every launch. iOS launches the app in the background for a silent push, and that launch needs the SDK too.
3. To read the data, call `handleBackgroundPush(userInfo:)` from the app delegate and call the completion handler yourself:

```swift
MessagingPushAPN.initialize(
    withConfig: MessagingPushConfigBuilder().build()
)

func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
) {
    switch MessagingPush.shared.handleBackgroundPush(userInfo: userInfo) {
    case .received(let push):
        // Key the work on push.deliveryID: the same push can arrive twice.
        refreshAccount(push.data, deliveryID: push.deliveryID) {
            completionHandler(.newData)
        }
    case .unsupported:
        completionHandler(.noData)
    case .notBackground:
        // Hand other pushes to any other handlers, then call completionHandler.
        completionHandler(.noData)
    }
}
```

Apps using `CioAppDelegateWrapper` put this method on the wrapped `AppDelegate`. FCM apps use `MessagingPushFCM.initialize` and the same handler.

Delivered doesn't depend on this handler. With `CioAppDelegateWrapper`, the SDK records it before the app's handler runs, and also when the app has no handler. Without the wrapper, `handleBackgroundPush(userInfo:)` records it. A push both see gets one receipt.

Silent pushes need no notification permission. The app still registers for remote notifications, which `autoFetchDeviceToken` does.

---

## 3. What the app has to plan for

- **About 30 seconds.** iOS gives the callback about 30 seconds of wall-clock time. Call the completion handler once, as soon as the work ends. Apps that run long or use a lot of power get woken less often.
- **Repeats.** The same push can arrive more than once. Key work on `deliveryID`.
- **Force-quit apps.** iOS doesn't wake an app the person swiped away in the app switcher. Pushes resume after they open it again.
- **Offline devices.** While a device is offline, APNs keeps only the newest push for the app, so an earlier silent push can be dropped. Customer.io sets a 24-hour expiry. Treat each push as a signal to sync, and fetch anything missed from your own backend.
- **Throttling.** Apple treats silent pushes as low priority and can delay or drop them, for example in Low Power Mode. Apple's guidance is no more than two or three an hour.

---

## 4. Results

| Result | Meaning | What the SDK records |
|---|---|---|
| `.received(push)` | A Customer.io silent push: `push.data`, `push.deliveryID`, `push.deliveryToken` | Delivered, once per delivery, when `autoTrackPushEvents` is on (already done by `CioAppDelegateWrapper`) |
| `.unsupported` | Marked as a Customer.io silent push, but an unknown version or bad metadata | Nothing |
| `.notBackground` | Any other push, including every push with `CIO-Delivery-ID` and `CIO-Delivery-Token` | Nothing |

---

## 5. How the SDK handles it

### Key Source Files

| File | Purpose |
|------|---------|
| `Sources/MessagingPush/BackgroundPush/BackgroundPush.swift` | Public types, payload parser, `handleBackgroundPush(userInfo:)`, `recordBackgroundPush(userInfo:)` |
| `Sources/MessagingPush/BackgroundPush/BackgroundPushReceiptSender.swift` | Saves and sends Delivered receipts |
| `Sources/MessagingPush/BackgroundPush/MessagingPush+BackgroundPushReceipts.swift` | Creates the receipt sender and starts it at `initialize` |
| `Sources/MessagingPush/Integration/CioProviderAgnosticAppDelegate.swift` | Records Delivered for pushes reaching the wrapper, then forwards them to the wrapped app delegate |

### Wire format, version 1

```json
{
  "aps": {"content-available": 1},
  "CIO-Background-Version": "1",
  "CIO-Background-Delivery-ID": "<delivery id>",
  "CIO-Background-Delivery-Token": "<device token the push was sent to>",
  "order_id": "A-1001"
}
```

Sent with `apns-push-type: background` and `apns-priority: 5`. Over Firebase the same object is `message.apns.payload`; Firebase adds `gcm.*` and `google.*` keys, which the parser drops from the data.

### Parsing rules

1. A complete `CIO-Delivery-ID` and `CIO-Delivery-Token` pair returns `.notBackground`, so existing push handling never changes.
2. Without any of the three `CIO-Background-*` keys above, the result is `.notBackground`.
3. With any of them, everything must hold or the result is `.unsupported`: version `"1"`, a non-blank delivery ID and token, `aps` exactly `{"content-available": 1}`, and every other value a string. Keys starting with `cio-` and the keys `notification`, `from`, `message_type` and `collapse_key` (any case) are reserved.

### Delivered receipts

- Saved to `Application Support/io.customer/background_push_receipts.json` before `handleBackgroundPush` returns or the wrapped app delegate is called, then sent as `Report Delivery Event` with `anonymousId` set to the delivery ID, `metric: delivered` and `recipient` set to the delivery token. The original receive time is kept.
- Sent with a `UIApplication` background task. Rows that fail are retried on the next push, the next `initialize`, or when Data Pipeline publishes a profile. 4xx answers other than 401, 403, 408 and 429 drop the row.
- One receipt per delivery: a repeat is skipped while a row for it is saved or after it was handled earlier in this launch (the last 100 deliveries). A repeat still triggers a send attempt, so a receipt left by a failed send goes out when the push arrives again.
- Before `MessagingPush.initialize`, the receipt is saved the same way and nothing is sent. `initialize` then sends it, or removes it when `autoTrackPushEvents` is off.
- The file and its folder use `completeUntilFirstUserAuthentication`, set on every write since each write replaces the file. Silent pushes wake the app while the device is locked, and an app whose entitlement defaults to `complete` protection could otherwise neither save nor send receipts then.

### App delegate wrapper

`CioProviderAgnosticAppDelegate`, the base of `CioAppDelegateWrapper`, has no `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` of its own. `forwardingTarget(for:)` hands that selector to a relay, which calls `recordBackgroundPush(userInfo:)` and then the wrapped app delegate with the same arguments. The app's handler is reached exactly as before, and a push gets its Delivered receipt even when the app doesn't call `handleBackgroundPush`.

`responds(to:)` answers yes when the wrapped app delegate implements the method, or when the app has the Remote notifications background mode, so apps without a handler still get receipts; the relay then completes with `.noData`. It answers no for an app that implements only the older `application(_:didReceiveRemoteNotification:)`, which UIKit calls only when the newer one is missing. An app's own subclass of the wrapper that implements the method runs instead of the relay and records nothing unless it calls `handleBackgroundPush`.

### App delegate proxies

Firebase's app delegate proxy (GoogleUtilities' `GULAppDelegateSwizzler`) subclasses the class of `UIApplication.shared.delegate` when Firebase is configured. Its `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` calls the implementation that class had at that moment. The wrapper class has none, so what happens depends on the GoogleUtilities version, exactly as before silent push support:

- **8.1.5 and later** forward to `forwardingTarget(for:)` when the class has no implementation (google/GoogleUtilities#247). The call reaches the relay, so Delivered is recorded and the app's handler runs once. This also covers SwiftUI's `UIApplicationDelegateAdaptor`, whose own app delegate forwards to the wrapper.
- **8.1.4 and earlier** call nothing more. Neither the app's handler nor the SDK sees the push: no data and no Delivered. Such apps need GoogleUtilities 8.1.5 or later (new installs resolve it; existing CocoaPods apps run `pod update GoogleUtilities`), or `FirebaseAppDelegateProxyEnabled` set to `NO`, in which case UIKit calls the wrapper directly and the SDK passes the APNs token to Firebase itself.

The wrapper adds no method of its own because the proxy would call it as the original in every version. It would then have to decide, for every push, whether to reach the app's handler, and the right answer differed by version: a Flutter app whose `firebase_messaging` registers with the proxy and as a `FlutterAppDelegate` plugin could get each message twice.

---

## 6. Wrapper SDKs

React Native, Flutter and Expo apps get Delivered from the native wrapper with no bridge change once they use an SDK with this support. Reading the data needs a bridge:

- iOS calls the handler on a background launch before JS or Dart is ready. A bridge calls `handleBackgroundPush` natively, hands `deliveryID`, `deliveryToken` and `data` across, and calls the completion handler itself if JS or Dart doesn't answer in time.
- Flutter apps that also use `firebase_messaging` see FCM data messages through both the proxy and `FlutterAppDelegate`; firebase_messaging releases since firebase/flutterfire#18830 pass each one to Dart once.
- The Expo plugin needs an option that adds the background mode and an app delegate subscriber that calls `handleBackgroundPush`.
