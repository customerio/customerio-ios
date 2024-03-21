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

        let workspaceSettings = AppState.shared.workspaceSettings
        if workspaceSettings.isSet() {
            CustomerIO.initialize(
                withConfig:
                SDKConfigBuilder(cdpApiKey: workspaceSettings.cdpApiKy)
                    .region(workspaceSettings.region)
                    .logLevel(.debug)
                    .build())
        }

        return true
    }
}
