import CioDataPipelines
import CioLiveActivities
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    let storage = DIGraphShared.shared.storage
    var deepLinkHandler = DIGraphShared.shared.deepLinksHandlerUtil

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).

        guard let windowScene = (scene as? UIWindowScene) else { return }

        window = UIWindow(windowScene: windowScene)
        setVisibleWindow()
        // The Visual Notification Inbox is placed directly in the Dashboard screen via the
        // public `NotificationInboxBell` / `NotificationInboxView` views (see DashboardViewController)
        // — the recommended integration — rather than a separate passthrough overlay window.

        // On a cold launch from a Live Activity tap, iOS delivers the `widgetURL` here in
        // `connectionOptions.urlContexts` rather than via `scene(_:openURLContexts:)`. Route it
        // through the same path so the deep link opens and the SDK reports the `opened` metric.
        handle(urlContexts: connectionOptions.urlContexts)

        // Universal links delivered while creating a scene arrive as user activities. Handle them
        // here as well as in `scene(_:continue:)` so cold and warm launches use the same route.
        handle(userActivities: connectionOptions.userActivities)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
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
        handle(urlContexts: URLContexts)
    }

    private func handle(urlContexts: Set<UIOpenURLContext>) {
        for context in urlContexts {
            var url = context.url
            // A tap on a Customer.io Live Activity arrives as a CIO tracking URL: report the
            // `opened` for the exact delivery shown and unwrap the customer's deep link (nil if
            // none). Non-CIO URLs are returned unchanged. Activities render from iOS 16.2, so this
            // must not be gated any higher — only the in-app routing below needs 17.2.
            guard let destination = CustomerIO.liveActivities.handleWidgetUrl(url) else { continue }
            url = destination
            if #available(iOS 17.2, *), url.host == LiveActivitiesViewController.deepLinkHost {
                routeToLiveActivities()
                continue
            }
            _ = deepLinkHandler.handleAppSchemeDeepLink(url)
        }
    }

    @available(iOS 17.2, *)
    private func routeToLiveActivities() {
        guard let nav = window?.rootViewController as? UINavigationController else { return }
        if nav.topViewController is LiveActivitiesViewController { return }
        nav.pushViewController(LiveActivitiesViewController(), animated: true)
    }

    // Universal links delivered directly by iOS belong to the scene. Customer.io-initiated deep
    // links use the SDKConfigBuilder.deepLinkCallback configured in AppDelegate.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        handle(userActivities: [userActivity])
    }

    private func handle(userActivities: Set<NSUserActivity>) {
        for userActivity in userActivities {
            guard let universalLinkUrl = userActivity.webpageURL else { continue }
            _ = deepLinkHandler.handleUniversalLinkDeepLink(universalLinkUrl)
        }
    }
}
