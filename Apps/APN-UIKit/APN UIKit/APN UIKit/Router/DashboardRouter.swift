import Foundation
import UIKit

protocol DashboardRouting {
    func routeToLogin()
    func routeToCustomDataScreen()
}

class DashboardRouter: DashboardRouting {
    weak var dashboardViewController: DashboardViewController?

    func routeToLogin() {
//        let viewController = LoginViewController.newInstance()
//        dashboardViewController?.navigationController?.pushViewController(viewController, animated: true)
        dashboardViewController?.navigationController?.popToRootViewController(animated: true)
    }
    
    func routeToCustomDataScreen() {
        let viewController = CustomDataViewController.newInstance()
        dashboardViewController?.navigationController?.pushViewController(viewController, animated: true)
    }
}
