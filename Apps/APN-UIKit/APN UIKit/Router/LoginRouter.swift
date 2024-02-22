import Foundation
import UIKit

protocol LoginRouting {
    func routeToDashboard()
    func routeToSettings(_ withInfo: [String: String]?)
}

class LoginRouter: LoginRouting {
    weak var loginViewController: LoginViewController?

    func routeToDashboard() {
        let viewController = DashboardViewController.newInstance()
        loginViewController?.navigationController?.pushViewController(viewController, animated: true)
    }

    func routeToSettings(_ withInfo: [String: String]? = nil) {
        let viewController = SettingsViewController.newInstance()
        if let siteId = withInfo?["site_id"], let cdpApiKey = withInfo?["cdp_api_key"] {
            viewController.deepLinkSiteId = siteId
            viewController.deeplinkCdpApiKey = cdpApiKey
        }
        loginViewController?.navigationController?.pushViewController(viewController, animated: true)
    }
}
