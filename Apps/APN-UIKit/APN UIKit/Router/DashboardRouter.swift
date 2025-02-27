import Foundation
import UIKit

protocol DashboardRouting {
    func routeToLogin()
    func routeToCustomDataScreen(forSource source: CustomDataSource)
    func routeToSettings(_ withInfo: [String: String]?)
    func routeToInlineSwiftUiExamplesScreen()
    func routeToInlineUikitExamplesScreen()
}

class DashboardRouter: DashboardRouting {
    weak var dashboardViewController: DashboardViewController?

    func routeToLogin() {
        if let controllers = dashboardViewController?.navigationController?.viewControllers, controllers.count >= 1 {
            if controllers[0] is LoginViewController {
                dashboardViewController?.navigationController?.popToRootViewController(animated: true)
            } else {
                dashboardViewController?.navigationController?.viewControllers = [LoginViewController.newInstance()]
            }
        }
    }

    func routeToCustomDataScreen(forSource source: CustomDataSource) {
        let viewController = CustomDataViewController.newInstance()
        viewController.source = source
        dashboardViewController?.navigationController?.pushViewController(viewController, animated: true)
    }

    func routeToSettings(_ withInfo: [String: String]? = nil) {
        let viewController = SettingsViewController.newInstance()
        if let siteId = withInfo?["site_id"], let cdpApiKey = withInfo?["cdp_api_key"] {
            viewController.deepLinkSiteId = siteId
            viewController.deeplinkCdpApiKey = cdpApiKey
        }
        dashboardViewController?.navigationController?.pushViewController(viewController, animated: true)
    }

    func routeToInlineSwiftUiExamplesScreen() {
        let viewController = InlineInAppMessageSwiftUiViewController.newInstance()
        dashboardViewController?.navigationController?.pushViewController(viewController, animated: true)
    }

    func routeToInlineUikitExamplesScreen() {
        let viewController = InlineInAppMessageUikitViewController.newInstance()
        dashboardViewController?.navigationController?.pushViewController(viewController, animated: true)
    }
}
