# Migration Guide — Customer.io iOS SDK (Reimplementation)

This document records the differences between the original Customer.io iOS SDK
(`customerio-ios`) and this reimplementation. It covers breaking API changes,
intentional behavior changes, and removals. Use it as a reference when porting
host apps or wrapper SDKs.

---

## Distribution

| | Original SDK | Reimplementation |
|---|---|---|
| **Package managers** | Swift Package Manager, CocoaPods | Swift Package Manager only |
| **CocoaPods** | Full support (`CustomerIODataPipelines`, `CustomerIOMessagingPushAPN`, etc.) | Not supported |

CocoaPods support is not planned for this reimplementation. Host apps using
CocoaPods must migrate to SPM before adopting the new SDK.

---

## Module Imports

The product and import names have changed across the board.

| Purpose | Original import | New import |
|---|---|---|
| Core / data pipeline | `CioDataPipelines` | `CustomerIO` |
| Push notifications (APN) | `CioMessagingPushAPN` | `CustomerIO_MessagingPush` |
| Push notifications (FCM) | `CioMessagingPushFCM` | `CustomerIO_MessagingPush` |
| In-app messaging | `CioMessagingInApp` | `CustomerIO_MessagingInApp` |
| Notification Service Extension | `CioMessagingPushAPN` (same target) | `CustomerIO_MessagingPushNSE` (separate target) |
| Location | `CioLocation` | `CustomerIO_Location` |

The old SDK also exposed internal modules (`CioInternalCommon`, `CioMessagingPush`)
that some NSE implementations imported directly. These have no equivalents —
use only the public module imports listed above.

---

## Push Notifications

### APN and FCM modules consolidated

The original SDK shipped two separate push targets: `MessagingPushAPN` (for
Apple Push Notification service) and `MessagingPushFCM` (for Firebase Cloud
Messaging). They shared a common `MessagingPush` base but required different
imports and initialization calls.

The reimplementation consolidates both into a single `CustomerIO_MessagingPush`
target. The push provider is selected at configuration time via the
`PushTokenProvider` protocol:

```swift
// Original — APN
import CioMessagingPushAPN
MessagingPushAPN.initialize(withConfig: MessagingPushConfigBuilder()
    .autoTrackPushEvents(true)
    .build())

// Original — FCM (required Firebase dependency)
import CioMessagingPushFCM
MessagingPushFCM.initialize(withConfig: MessagingPushConfigBuilder()
    .autoTrackPushEvents(true)
    .build())

// New — both APN and FCM use the same import and config block
import CustomerIO_MessagingPush
SdkConfigBuilder(cdpApiKey: "…")
    .push {
        PushConfigBuilder(provider: APNPushProvider())   // or a custom PushTokenProvider for FCM
            .autoTrackPushEvents(true)
            .showInForeground(true)
    }
```

### No Firebase dependency

The original FCM module had a direct dependency on the Firebase SDK. The
reimplementation removes this: FCM support is achieved by implementing the
`PushTokenProvider` protocol and injecting it via `PushConfigBuilder(provider:)`.
The Firebase SDK itself is not imported by the Customer.io SDK.

### Configuration option rename

`showPushAppInForeground` has been renamed to `showInForeground`:

```swift
// Original
MessagingPushConfigBuilder().showPushAppInForeground(true)

// New
PushConfigBuilder(provider: APNPushProvider()).showInForeground(true)
```

### `autoFetchDeviceToken` removed from public config

The original SDK exposed `autoFetchDeviceToken(Bool)` on
`MessagingPushConfigBuilder`. In the reimplementation this is an internal
implementation detail of `APNPushProvider` and is not configurable from the
public API.

### Notification Service Extension — separate module and subclass pattern

The original SDK initialized the NSE inline inside
`UNNotificationServiceExtension` overrides:

```swift
// Original
import CioInternalCommon
import CioMessagingPush
import CioMessagingPushAPN

class NotificationService: UNNotificationServiceExtension {
    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        MessagingPushAPN.initializeForExtension(
            withConfig: MessagingPushConfigBuilder(cdpApiKey: "…").build()
        )
        MessagingPush.shared.didReceive(request, withContentHandler: contentHandler)
    }

    override func serviceExtensionTimeWillExpire() {
        MessagingPush.shared.serviceExtensionTimeWillExpire()
    }
}
```

The reimplementation provides a dedicated `CustomerIO_MessagingPushNSE` target
with a base class to subclass instead:

```swift
// New
import CustomerIO_MessagingPushNSE

class NotificationService: CIONotificationServiceExtension {
    init() {
        super.init(cdpApiKey: "…")
    }
}
```

`CIONotificationServiceExtension` implements the two `UNNotificationServiceExtension`
lifecycle methods internally. Override them only if you need custom behavior
beyond what the base class provides.

The NSE target is intentionally minimal — it links only against Foundation and
UserNotifications, keeping the extension binary small.

### AppDelegate forwarding — wrapper class removed

The original SDK offered `CioAppDelegateWrapper<YourAppDelegate>` to intercept
push delegate calls without modifying the host app's `AppDelegate`:

```swift
// Original
@main
class AppDelegateWithCioIntegration: CioAppDelegateWrapper<AppDelegate> {}
```

The reimplementation removes this pattern. Forward push delegate calls
explicitly from your own `AppDelegate`:

```swift
// New
func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    cio.push.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
}

func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
) {
    cio.push.didFailToRegisterForRemoteNotifications(withError: error)
}
```

### Behavior change — third-party push foreground presentation

**Original behavior:** `showPushAppInForeground` was applied to all notifications
uniformly. If set to `false`, third-party (non-CIO) local notifications were
also suppressed when the app was in the foreground.

**New behavior:** `showInForeground` applies only to CIO pushes. Third-party
and local notifications are always presented in the foreground regardless of
this flag. The SDK must not suppress notifications it does not own.

---

## Initialization and Configuration

### Single builder, single configure call

The original SDK required a separate initialize call per module:

```swift
// Original
CustomerIO.initialize(withConfig: SDKConfigBuilder(cdpApiKey: "…")
    .region(.us)
    .build())

MessagingPushAPN.initialize(withConfig: MessagingPushConfigBuilder()
    .autoTrackPushEvents(true)
    .build())

MessagingInApp
    .initialize(withConfig: MessagingInAppConfigBuilder(siteId: "…", region: .us).build())
    .setEventListener(self)
```

The reimplementation uses a single builder that composes all module
configurations, and a single configure call:

```swift
// New
let config = SdkConfigBuilder(cdpApiKey: "…")
    .region(.us)
    .push {
        PushConfigBuilder(provider: APNPushProvider())
            .autoTrackPushEvents(true)
            .showInForeground(true)
    }
    .inApp {
        MessagingInAppConfigBuilder(siteId: "…")
    }
    .build()

cio.startConfigure(config) { error in
    cio.inApp.setEventListener(self)
}
```

### `region` no longer required in MessagingInApp config

The original `MessagingInAppConfigBuilder` required a `region` parameter.
In the reimplementation the region is inherited from the core SDK configuration
and `MessagingInAppConfigBuilder` takes only `siteId`:

```swift
// Original
MessagingInAppConfigBuilder(siteId: "…", region: .us)

// New
MessagingInAppConfigBuilder(siteId: "…")
```

### No static singleton — explicit instance required

The original SDK exposed `CustomerIO.shared` as a static singleton. Host apps
called `CustomerIO.initialize(…)` once and then accessed `CustomerIO.shared`
everywhere.

The reimplementation has no static singleton in the SDK itself. Host apps
create and own the `CustomerIO` instance:

```swift
// Original
CustomerIO.initialize(withConfig: …)
CustomerIO.shared.track("event")

// New
let cio = CustomerIO()   // created at app scope, before configure
cio.startConfigure(config)
cio.track("event")
```

Events tracked on the `CustomerIO` instance before `startConfigure` completes
are buffered and drained in order once configuration finishes.

### Module accessors available immediately after `startConfigure`

The original SDK's module accessors could crash if called before the module
finished initializing asynchronously. In the reimplementation, module instances
are registered synchronously during `activateModulesForLaunch` (called by
`startConfigure` before its async Task is enqueued). This means `cio.push` and
`cio.inApp` are safe to access immediately after `startConfigure` returns,
though properties backed by storage (such as `registeredDeviceToken`) will
return `nil` until the async configure completes.

### `startConfigure` vs `configure`

`startConfigure(_:onCompletion:)` is the recommended entry point. It calls
`activateModulesForLaunch` synchronously — which must happen before
`application(_:didFinishLaunchingWithOptions:)` returns in order to register
as `UNUserNotificationCenter.delegate` in time — then dispatches the async
work in a detached `Task`.

The `async configure(_:)` overload exists for call sites that can `await`, but
callers must invoke `activateModulesForLaunch(_:)` manually before scheduling
the task.

---

## Runtime SDK Access

### Module accessor pattern

Modules are accessed as properties on the `CustomerIO` instance rather than
via their own singletons:

```swift
// Original
MessagingPush.shared.registeredDeviceToken
MessagingInApp.shared.setEventListener(self)

// New
cio.push.registeredDeviceToken
cio.inApp.setEventListener(self)
```

Accessing a module that was not included in `SdkConfigBuilder` triggers a
`fatalError`. Accessing a module before `startConfigure` has been called
triggers a `fatalError` with a message directing the caller to `startConfigure`.

---

## Removed Features

| Feature | Status |
|---|---|
| CocoaPods distribution | Removed. SPM only. |
| `CioAppDelegateWrapper` | Removed. Forward delegate calls manually. |
| `CustomerIO.shared` singleton | Removed. Own and inject the `CustomerIO` instance. |
| Firebase / `CioMessagingPushFCM` | Removed. Use `PushTokenProvider` protocol. |
| `MessagingPushAPN.initializeForExtension` | Removed. Subclass `CIONotificationServiceExtension`. |
| `autoFetchDeviceToken` config option | Removed. Internal to `APNPushProvider`. |
| `migrationSiteId` config option | Removed. Legacy Journeys migration tooling is not carried forward. |
| `trackApplicationLifecycleEvents` | Removed. Not implemented in the reimplementation. |
