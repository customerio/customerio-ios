import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    let storage = DIGraph.shared.storage
    var deepLinkHandler = DIGraph.shared.deepLinksHandlerUtil

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).

        guard let windowScene = (scene as? UIWindowScene) else { return }

        window = UIWindow(windowScene: windowScene)
        setVisibleWindow()
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
            let navigationController = UINavigationController(rootViewController: DashboardViewController
                .newInstance())
            window?.rootViewController = navigationController
        } else {
            let navigationController = UINavigationController(rootViewController: LoginViewController.newInstance())
            window?.rootViewController = navigationController
        }
        window?.makeKeyAndVisible()
    }

    // Opens one or more URLs, handles deep link for the apps
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            let url = context.url
            _ = deepLinkHandler.handleAppSchemeDeepLink(url)
        }
    }

    // Universal Links - handling universal links that come into the mobile app, not from the Customer.io SDK.
    // To handle Universal Links from the Customer.io SDK, see `AppDelegate` file for implementation.
    // Learn more: https://customer.io/docs/sdk/ios/push/#universal-links-deep-links
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let universalLinkUrl = userActivity.webpageURL else {
            return
        }

        _ = deepLinkHandler.handleUniversalLinkDeepLink(universalLinkUrl)
    }
}
