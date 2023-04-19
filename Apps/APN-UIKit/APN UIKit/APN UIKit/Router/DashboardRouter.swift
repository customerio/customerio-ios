import Foundation
import UIKit

protocol DashboardRouting {
    func routeToLogin()
    func routeToCustomDataScreen(forSource source : CustomDataSource)
    func routeToSettings()
}

class DashboardRouter: DashboardRouting {
    weak var dashboardViewController: DashboardViewController?

    func routeToLogin() {
        guard let _ = dashboardViewController?.navigationController?.popToRootViewController(animated: true) else {
            let viewController = LoginViewController.newInstance()
            dashboardViewController?.navigationController?.pushViewController(viewController, animated: true)
            return
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
}
