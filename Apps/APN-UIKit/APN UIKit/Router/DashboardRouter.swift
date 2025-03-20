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
    lazy var settingsRouter: SettingsRouting = SettingsRouter(navigationController: dashboardViewController?.navigationController)

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
        settingsRouter.routeToMainSettings(siteIdOverride: withInfo?["site_id"], cdpApiKeyOverride: withInfo?["cdp_api_key"])
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
