import CioTracking
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication
            .LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        /*

         How do I get the values for the siteId and apiKy?
         You can find/create them here: https://fly.customer.io/settings/api_credentials
         For more information about workspaces checkout these
         docs: https://customer.io/docs/accounts-and-workspaces/workspaces/
         */

        let workspaceSettings = AppState.shared.workspaceSettings
        if workspaceSettings.isSet() {
            CustomerIO.initialize(
                siteId: workspaceSettings.siteId,
                apiKey: workspaceSettings.apiKey,
                region: workspaceSettings.region
            ) { config in
                // Debug config just to make the demo
                // easier. You can learn more about these configs
                // here: https://customer.io/docs/sdk/ios/getting-started/#configuration-options
                config.backgroundQueueMinNumberOfTasks = 1
                config.backgroundQueueSecondsDelay = 0
                config.logLevel = .debug
            }
        }

        return true
    }
}
