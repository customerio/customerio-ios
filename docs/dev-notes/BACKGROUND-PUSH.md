# Silent (Background) Push

A silent push wakes the app in the background and hands it data. Nothing is shown to the person, and Opened never applies. This note covers what an app needs and how the SDK handles it.

---

## 1. Minimum version

Silent push needs customerio-ios **5.2.0** or later, the first release with `MessagingPush.handleBackgroundPush(userInfo:)`. It ships as a `feat`, so semantic-release makes it the next minor version; update this number if another minor release lands first.

Older SDKs never report `cio_background_push_version`, and Customer.io sends silent pushes only to devices reporting `"1"`, so devices on older versions are skipped.

---

## 2. App setup

1. In Xcode, add **Background Modes → Remote notifications**. Info.plist `UIBackgroundModes` then lists `remote-notification`.
2. Turn on `backgroundPushEnabled(true)` and initialize MessagingPush in `application(_:didFinishLaunchingWithOptions:)` on every launch. iOS launches the app in the background for a silent push, and that launch needs the SDK too.
3. Call `handleBackgroundPush(userInfo:)` from the app delegate and call the completion handler yourself:

```swift
MessagingPushAPN.initialize(
    withConfig: MessagingPushConfigBuilder()
        .backgroundPushEnabled(true)
        .build()
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
| `.received(push)` | A Customer.io silent push: `push.data`, `push.deliveryID`, `push.deliveryToken` | Delivered, once per delivery, when `autoTrackPushEvents` is on |
| `.unsupported` | Marked as a Customer.io silent push, but an unknown version or bad metadata | Nothing |
| `.notBackground` | Any other push, including every push with `CIO-Delivery-ID` and `CIO-Delivery-Token` | Nothing |

---

## 5. How the SDK handles it

### Key Source Files

| File | Purpose |
|------|---------|
| `Sources/MessagingPush/BackgroundPush/BackgroundPush.swift` | Public types, payload parser, `handleBackgroundPush(userInfo:)` |
| `Sources/MessagingPush/BackgroundPush/BackgroundPushReceiptSender.swift` | Saves and sends Delivered receipts |
| `Sources/MessagingPush/BackgroundPush/BackgroundPushReadiness.swift` | Readiness check and setup at `initialize` |
| `Sources/DataPipeline/DataPipelineImplementation.swift` | Adds `cio_background_push_version` to device updates |
| `Sources/MessagingPush/Integration/CioProviderAgnosticAppDelegate.swift` | Forwards the remote-notification callback to the wrapped app delegate |

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

- Saved to `Application Support/io.customer/background_push_receipts.json` before `handleBackgroundPush` returns, then sent as `Report Delivery Event` with `anonymousId` set to the delivery ID, `metric: delivered` and `recipient` set to the delivery token. The original receive time is kept.
- Sent with a `UIApplication` background task. Rows that fail are retried on the next push, the next `initialize`, or when Data Pipeline publishes a profile. 4xx answers other than 401, 403, 408 and 429 drop the row.
- One receipt per delivery: a repeat is skipped while a row for it is saved or after it was handled earlier in this launch (the last 100 deliveries). A repeat still triggers a send attempt, so a receipt left by a failed send goes out when the push arrives again.
- Before `MessagingPush.initialize`, the receipt is saved the same way and nothing is sent. `initialize` then sends it, or removes it when `autoTrackPushEvents` is off.

### Readiness

`cio_background_push_version` is set last on every `Device Created or Updated`, so custom device attributes can't override it. It is `"1"` when `backgroundPushEnabled` is on and Info.plist lists `remote-notification`, and `"0"` otherwise, including apps that never initialize MessagingPush. MessagingPush posts `BackgroundPushReadinessChangedEvent` from `initialize`. Data Pipeline sends a device update for it only when the value differs from the last device update, so a launch with unchanged readiness sends nothing extra. The last value is saved in `GlobalDataStore.reportedBackgroundPushVersion` once the event gets past Analytics' in-memory startup queue, so an update lost to the app being killed before then is sent again on the next launch.

### App delegate proxies

Firebase's app delegate proxy (GoogleUtilities' `GULAppDelegateSwizzler`) subclasses the class of `UIApplication.shared.delegate` when Firebase is configured. Its `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` calls only the implementation that class had at that moment and never asks `forwardingTarget(for:)`. Two classes need one:

- `CioProviderAgnosticAppDelegate` adds the method to itself at runtime and forwards it to the wrapped app delegate. Adding it at runtime keeps an app's subclass that already implements the method compiling without `override`. `responds(to:)` still answers for the wrapped delegate, so UIKit calls it only when the app handles background pushes.
- With `@UIApplicationDelegateAdaptor`, `UIApplication.shared.delegate` is SwiftUI's own app delegate, which forwards the callback without implementing it. The wrapper's `application(_:didFinishLaunchingWithOptions:)` adds a forwarder to that class before calling the wrapped delegate, where apps usually call `FirebaseApp.configure()`.

A call that arrives through such a proxy reaches the app only when `backgroundPushEnabled` is on, as some apps must not get it: Flutter's `FlutterAppDelegate` would hand the push to `firebase_messaging`, which also registers with the proxy directly and so would see it twice. UIKit's own calls, without a proxy, always reach the app.

Still unhandled: a SwiftUI app with Firebase's proxy on and **without** `CioAppDelegateWrapper` never gets the callback, and neither does one that configures Firebase before the wrapper's `didFinishLaunching` (for example in the `App` initializer). Those apps can set `FirebaseAppDelegateProxyEnabled` to `NO` in Info.plist; the SDK passes the APNs token to Firebase itself.

---

## 6. Wrapper SDKs

React Native, Flutter and Expo need their own follow-up before general release. The pilot covers native apps only. Until a wrapper turns on `backgroundPushEnabled`, its apps report `"0"` and the app delegate forwarder passes nothing new to them.

- Push config reaches the wrappers through `MessagingPushConfigBuilder.build(from:)` or generated code, and neither has a `backgroundPushEnabled` key yet.
- iOS calls the handler on a background launch before JS or Dart is ready. A bridge calls `handleBackgroundPush` natively, hands `deliveryID`, `deliveryToken` and `data` across, and calls the completion handler itself if JS or Dart doesn't answer in time.
- Flutter apps that also use `firebase_messaging` would get each FCM data message twice once the wrapper opts in, as `FlutterAppDelegate` forwards the proxy's call to that plugin again. The bridge should handle Customer.io silent pushes before plugins see them.
- The Expo plugin needs an option that adds the background mode, the builder call and an app delegate subscriber that calls `handleBackgroundPush`.
