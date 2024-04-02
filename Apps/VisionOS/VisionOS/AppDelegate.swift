import UIKit

import CioDataPipelines

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication
            .LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        /*

         You will need cdpApiKey to initialize CustomerIO
         Learn more about it here: https://customer.io/docs/sdk/ios/quick-start-guide/#prerequisites
         */

        // Uncomment the following line and set CDP API Key if it is more convenient than setting it in the UI
        // AppState.shared.workspaceSettings.cdpApiKy = "CDP_API_KEY"

        let workspaceSettings = AppState.shared.workspaceSettings
        if workspaceSettings.isSet() {
            CustomerIO.initialize(
                withConfig:
                SDKConfigBuilder(cdpApiKey: workspaceSettings.cdpApiKy)
                    .logLevel(.debug)
                    .build())
        }

        return true
    }
}
