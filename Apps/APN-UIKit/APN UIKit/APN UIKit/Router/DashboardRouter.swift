import Foundation
import UIKit

protocol DashboardRouting {
    func routeToLogin()
    func routeToCustomDataScreen(forSource source: CustomDataSource)
    func routeToSettings()
    func routeToDeepLinkScreen(withInfo : [String:String])
}

class DashboardRouter: DashboardRouting {
    weak var dashboardViewController: DashboardViewController?

    func routeToLogin() {
        if let controllers = dashboardViewController?.navigationController?.viewControllers, controllers.count >= 1 {
            if controllers[0] is LoginViewController {
                dashboardViewController?.navigationController?.popToRootViewController(animated: true)
            }
            else {
                dashboardViewController?.navigationController?.viewControllers = [LoginViewController.newInstance()]
            }
        }
    }

    func routeToCustomDataScreen(forSource source: CustomDataSource) {
        let viewController = CustomDataViewController.newInstance()
        viewController.source = source
        dashboardViewController?.navigationController?.pushViewController(viewController, animated: true)
    }

    func routeToSettings() {
        let viewController = SettingsViewController.newInstance()
        dashboardViewController?.navigationController?.pushViewController(viewController, animated: true)
    }
    
    func routeToDeepLinkScreen(withInfo : [String:String]) {
        let viewController = DeepLinkViewController.newInstance()
        viewController.deepLinkInfo = withInfo
        dashboardViewController?.navigationController?.present(viewController, animated: true)
    }
}
