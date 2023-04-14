import UIKit
import CioTracking

@main
class AppDelegate: UIResponder, UIApplicationDelegate {



    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        // Register for remote notifications using APN. On successful registration,
        // didRegisterForRemoteNotifications delegate method will be called and it
        // provides a device token. In case, registration fails then
        // didFailToRegisterForRemoteNotifications will be called.
        application.registerForRemoteNotifications()
        
        initializeCioSDK()
        return true
    }

    func initializeCioSDK() {
        // Initialise CustomerIO SDK
        // TODO: - Update this when using local storage for configurations
        CustomerIO.initialize(siteId: Env.customerIOSiteId, apiKey: Env.customerIOApiKey, region: Region.US, configure: { config in
            config.logLevel = .debug
            config.autoTrackScreenViews = true
        })
    }
    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        
    }

}

