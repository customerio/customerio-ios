import CioDataPipelines
import CioMessagingInApp
import CioMessagingPushAPN
import CioLocation
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Minimal SDK initialization to verify the dependency graph resolves correctly.
        // Replace placeholders with real credentials when testing full functionality.
        let config = SDKConfigBuilder(cdpApiKey: "YOUR_CDP_API_KEY")
            .migrationSiteId("YOUR_SITE_ID")
            .build()

        CustomerIO.initialize(withConfig: config)
        MessagingInApp.initialize(withConfig: MessagingInAppConfigBuilder(siteId: "YOUR_SITE_ID", apiKey: "YOUR_API_KEY").build())

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        MessagingPushAPN.shared.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        MessagingPushAPN.shared.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }
}
