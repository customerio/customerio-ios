import CioDataPipelines
import CioLiveActivities
import SampleAppsCommon
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    let storage = DIGraphShared.shared.storage
    var deepLinkHandler = DIGraphShared.shared.deepLinksHandlerUtil

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        if LifecycleTraceHarness.sharedRecorder?.scenario.isColdStart == true {
            LifecycleTraceHarness.sharedRecorder?.record(
                callback: .sceneWillConnect,
                owner: .sceneDelegate,
                kind: .osCallback,
                phase: .entry,
                observations: LifecycleTraceEvidence.observe(scene: scene, callback: .sceneWillConnect),
                LifecycleTraceEvidence.observe(connectionOptions: connectionOptions)
            )
        }

        guard let windowScene = (scene as? UIWindowScene) else { return }

        window = UIWindow(windowScene: windowScene)
        setVisibleWindow()
        // The Visual Notification Inbox is placed directly in the Dashboard screen via the
        // public `NotificationInboxBell` / `NotificationInboxView` views (see DashboardViewController)
        // — the recommended integration — rather than a separate passthrough overlay window.

        // On a cold launch from a Live Activity tap, iOS delivers the `widgetURL` here in
        // `connectionOptions.urlContexts` rather than via `scene(_:openURLContexts:)`. Route it
        // through the same path so the deep link opens and the SDK reports the `opened` metric.
        if handle(urlContexts: connectionOptions.urlContexts) {
            LifecycleTraceHarness.endScenario(after: .hostURLRoute)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
        recordSceneStateChange(.sceneDidDisconnect, scene)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        recordSceneStateChange(.sceneDidBecomeActive, scene)
        LifecycleTraceHarness.endScenario(after: .activeScene)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
        recordSceneStateChange(.sceneWillResignActive, scene)
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
        recordSceneStateChange(.sceneWillEnterForeground, scene)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
        recordSceneStateChange(.sceneDidEnterBackground, scene)
    }

    private func recordSceneStateChange(_ callback: LifecycleTraceCallback, _ scene: UIScene) {
        LifecycleTraceHarness.sharedRecorder?.record(
            callback: callback,
            owner: .sceneDelegate,
            kind: .osCallback,
            phase: .stateChange,
            observations: LifecycleTraceEvidence.observe(scene: scene, callback: callback)
        )
    }

    // Set visible window based on user login status
    func setVisibleWindow() {
        // If previous user is not a guest login and credentials were used to login into the app
        if let _ = storage.userEmailId {
            let navigationController = UINavigationController(
                rootViewController: DashboardViewController
                    .newInstance()
            )
            window?.rootViewController = navigationController
        } else {
            let navigationController = UINavigationController(rootViewController: LoginViewController.newInstance())
            window?.rootViewController = navigationController
        }
        window?.makeKeyAndVisible()
    }

    // Opens one or more URLs, handles deep link for the apps
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        let shouldTrace = URLContexts.count == 1
        if shouldTrace {
            LifecycleTraceHarness.sharedRecorder?.record(
                callback: .sceneOpenURLContexts,
                owner: .sceneDelegate,
                kind: .osCallback,
                phase: .entry,
                observations: LifecycleTraceEvidence.observe(scene: scene),
                LifecycleTraceEvidence.observe(urlContexts: URLContexts)
            )
        }
        if handle(urlContexts: URLContexts, shouldTrace: shouldTrace) {
            LifecycleTraceHarness.endScenario(after: .hostURLRoute)
        }
    }

    @discardableResult
    private func handle(urlContexts: Set<UIOpenURLContext>, shouldTrace: Bool? = nil) -> Bool {
        let shouldTraceRoute = shouldTrace ?? (urlContexts.count == 1)
        var tracedRoute = false
        for context in urlContexts {
            tracedRoute = handle(urlContext: context, shouldTrace: shouldTraceRoute) || tracedRoute
        }
        return tracedRoute
    }

    private func handle(urlContext context: UIOpenURLContext, shouldTrace: Bool) -> Bool {
        var url = context.url
        // A tap on a Customer.io Live Activity arrives as a CIO tracking URL: report the
        // `opened` for the exact delivery shown and unwrap the customer's deep link (nil if
        // none). Non-CIO URLs are returned unchanged. Activities render from iOS 16.2, so this
        // must not be gated any higher — only the in-app routing below needs 17.2.
        let traceRoute = shouldTrace && LifecycleTraceEvidence.isTraceableURLRoute(url)
        let routeEvidence = LifecycleTraceEvidence.observe(url: url)
        if traceRoute {
            recordHostRouteIntent(evidence: routeEvidence)
        }
        let isCustomerIORoute = LifecycleTraceEvidence.isCustomerIOLiveActivityRoute(url)
        if traceRoute, isCustomerIORoute {
            recordCustomerIORoute(evidence: routeEvidence, phase: .intent)
        }
        let destination = CustomerIO.liveActivities.handleWidgetUrl(url)
        if traceRoute, isCustomerIORoute {
            recordCustomerIORoute(
                evidence: routeEvidence,
                phase: .result,
                routingResult: Self.widgetRoutingResult(original: url, destination: destination)
            )
        }
        guard let destination = destination else {
            if traceRoute {
                recordHostRouteResult(evidence: routeEvidence, handled: true)
            }
            return traceRoute
        }
        url = destination
        let handled: Bool
        if #available(iOS 17.2, *), url.host == LiveActivitiesViewController.deepLinkHost {
            handled = routeToLiveActivities()
        } else {
            handled = deepLinkHandler.handleAppSchemeDeepLink(url)
        }
        if traceRoute {
            recordHostRouteResult(evidence: routeEvidence, handled: handled)
        }
        return traceRoute
    }

    // `handleWidgetUrl` returns nil for a consumed CIO tracking URL without a redirect, the
    // unwrapped deep link for one with a redirect, and the input unchanged for non-CIO URLs.
    private static func widgetRoutingResult(original: URL, destination: URL?) -> LifecycleTraceRoutingResult {
        guard let destination = destination else { return .handled }
        return destination == original ? .unhandled : .redirect
    }

    @available(iOS 17.2, *)
    private func routeToLiveActivities() -> Bool {
        guard let nav = window?.rootViewController as? UINavigationController else { return false }
        if nav.topViewController is LiveActivitiesViewController { return true }
        nav.pushViewController(LiveActivitiesViewController(), animated: true)
        return true
    }

    private func recordHostRouteIntent(evidence: LifecycleTraceObservation) {
        LifecycleTraceHarness.sharedRecorder?.record(
            callback: .hostRouteURL,
            owner: .host,
            kind: .hostRouting,
            phase: .intent,
            observations: evidence
        )
    }

    private func recordCustomerIORoute(
        evidence: LifecycleTraceObservation,
        phase: LifecycleTracePhase,
        routingResult: LifecycleTraceRoutingResult? = nil
    ) {
        if let routingResult {
            LifecycleTraceHarness.sharedRecorder?.record(
                callback: .customerIORouteDeepLink,
                owner: .customerIOSDK,
                kind: .sdkRouting,
                phase: phase,
                observations: evidence,
                LifecycleTraceEvidence.observe(routingResult: routingResult)
            )
        } else {
            LifecycleTraceHarness.sharedRecorder?.record(
                callback: .customerIORouteDeepLink,
                owner: .customerIOSDK,
                kind: .sdkRouting,
                phase: phase,
                observations: evidence
            )
        }
    }

    private func recordHostRouteResult(evidence: LifecycleTraceObservation, handled: Bool) {
        LifecycleTraceHarness.sharedRecorder?.record(
            callback: .hostRouteURL,
            owner: .host,
            kind: .hostRouting,
            phase: .result,
            observations: evidence,
            LifecycleTraceEvidence.observe(routingResult: handled ? .handled : .unhandled)
        )
    }

    // Universal Links - handling universal links that come into the mobile app, not from the Customer.io SDK.
    // To handle Universal Links from the Customer.io SDK, see `AppDelegate` file for implementation.
    // Learn more: https://customer.io/docs/sdk/ios/push/#universal-links-deep-links
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        LifecycleTraceHarness.sharedRecorder?.record(
            callback: .sceneContinueUserActivity,
            owner: .sceneDelegate,
            kind: .osCallback,
            phase: .entry,
            observations: LifecycleTraceEvidence.observe(scene: scene),
            LifecycleTraceEvidence.observe(userActivity: userActivity)
        )

        guard let universalLinkUrl = userActivity.webpageURL else {
            return
        }

        let routeEvidence = LifecycleTraceEvidence.observe(userActivity: userActivity)
        LifecycleTraceHarness.sharedRecorder?.record(
            callback: .hostRouteUserActivity,
            owner: .host,
            kind: .hostRouting,
            phase: .intent,
            observations: routeEvidence
        )
        let handled = deepLinkHandler.handleUniversalLinkDeepLink(universalLinkUrl)
        LifecycleTraceHarness.sharedRecorder?.record(
            callback: .hostRouteUserActivity,
            owner: .host,
            kind: .hostRouting,
            phase: .result,
            observations: routeEvidence,
            LifecycleTraceEvidence.observe(routingResult: handled ? .handled : .unhandled)
        )
        LifecycleTraceHarness.endScenario(after: .hostUserActivityRoute)
    }
}
