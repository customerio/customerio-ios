import Foundation
import UIKit

@MainActor
protocol LoginRouting {
    func routeToDashboard()
    func routeToSettings(_ withInfo: [String: String]?)
    func routeToDeepLinkScreen(withInfo: [String: String])
}

class LoginRouter: LoginRouting {
    weak var loginViewController: LoginViewController?
    lazy var settingsRouter: SettingsRouting = SettingsRouter(navigationController: loginViewController?.navigationController)

    func routeToDashboard() {
        let viewController = DashboardViewController.newInstance()
        loginViewController?.navigationController?.pushViewController(viewController, animated: true)
    }

    func routeToSettings(_ withInfo: [String: String]? = nil) {
        settingsRouter.routeToMainSettings(siteIdOverride: withInfo?["site_id"], cdpApiKeyOverride: withInfo?["cdp_api_key"])
    }

    func routeToDeepLinkScreen(withInfo: [String: String]) {
        let viewController = DeepLinkViewController.newInstance()
        viewController.deepLinkInfo = withInfo
        loginViewController?.navigationController?.present(viewController, animated: true)
    }
}
