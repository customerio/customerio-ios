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
         1- Login or Signup in CustomerIO platform: https://fly.customer.io/
         2- On the top right section click the
         Settings Icon >> Workspace Settings >> API and webhook credentials
         You will see list of one or more workspaces and each has
         its own pair of siteId and apiKey, these are the ones
         to use here.
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
        
        // If user already logged in, let's
        // call identify
        let profile = AppState.shared.profile
        if profile.loggedIn {
            CustomerIO.shared.identify(
                identifier: profile.id,
                body: profile.properties.toDictionary())
        }

        return true
    }
}
