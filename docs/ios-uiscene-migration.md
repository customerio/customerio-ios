# Native UIScene migration

Building with a toolchain that requires scene adoption changes how iOS delivers lifecycle events to
your app. It does not move every app-delegate responsibility into a scene delegate, and it does not
require an app to support multiple simultaneous windows.

## Ownership after scene adoption

Keep these responsibilities in `UIApplicationDelegate`:

- Customer.io SDK initialization
- APNs device-token registration callbacks
- notification-center delegate integration
- `SDKConfigBuilder.deepLinkCallback(_:)` for links initiated by Customer.io actions

Move OS-delivered UI events to `UISceneDelegate`:

- warm URL opens in `scene(_:openURLContexts:)`
- cold URL opens in `connectionOptions.urlContexts`
- warm universal links in `scene(_:continue:)`
- cold universal links in `connectionOptions.userActivities`

The SDK does not choose a scene on the host's behalf. A scene-based host owns the decision about
which scene should present or navigate for a URL.

## Configure Customer.io-initiated deep links

Register the public callback while building the SDK configuration:

```swift
let config = SDKConfigBuilder(cdpApiKey: "...")
    .deepLinkCallback { url in
        guard appRouter.canHandle(url) else { return false }
        DispatchQueue.main.async { appRouter.handle(url) }
        return true
    }

CustomerIO.initialize(withConfig: config.build())
```

The SDK retains this callback for the app's lifetime. Capture app-owned routers or coordinators
weakly when they should not be retained for that lifetime.

Return `true` when the host handled the URL. Returning `false` preserves the SDK fallback chain: it
tries the legacy app-delegate continuation callback for universal links, then asks the system to open
the URL.

## Receive URLs in a scene

Use the same routing path for cold and warm delivery:

```swift
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        connectionOptions.urlContexts.forEach { route($0.url) }
        connectionOptions.userActivities.compactMap(\.webpageURL).forEach { route($0) }
    }

    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        contexts.forEach { route($0.url) }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let url = userActivity.webpageURL else { return }
        route(url)
    }

    private func route(_ url: URL) {
        appRouter.handle(url)
    }
}
```

If the host uses Customer.io Live Activities, import `CioLiveActivities` and unwrap each URL before
normal app routing:

```swift
guard let destination = CustomerIO.liveActivities.handleWidgetUrl(url) else { return }
appRouter.handle(destination)
```

`handleWidgetUrl(_:)` reports the opened metric for a Customer.io Live Activity tracking URL and
returns the customer destination. Non-Customer.io URLs are returned unchanged.

## Legacy apps remain supported

Apps that have not adopted scenes can keep their existing app-delegate lifecycle callbacks. In a
legacy host, `application(_:open:options:)` can receive app URL opens and Live Activity taps.

For Customer.io-initiated universal links, the SDK directly invokes
`application(_:continue:restorationHandler:)` as its fallback when `deepLinkCallback` is absent or
returns `false`, regardless of whether the host uses scenes. A scene-based host can omit that fallback
when its `deepLinkCallback` handles every intended link. OS-delivered universal links still belong in
`scene(_:continue:)` after scene adoption.

Do not implement both paths for the same OS-delivered event unless the host deliberately supports
both lifecycle models. Initialize the SDK once in the app delegate in either model.

## Multiple windows are separate

Scene adoption and multiple-window support are not the same feature. A single-window scene app can
adopt this lifecycle without enabling `UIApplicationSupportsMultipleScenes`.

For a true multi-window app, the host must decide which scene owns navigation and presentation. The
SDK remains app-scoped and does not provide per-scene SDK instances or select a window for the host.
Tracking and push handling remain app-wide. SDK-managed UI is not scene-addressable, so a host with
multiple simultaneous foreground scenes should not rely on the SDK to select a particular window.
