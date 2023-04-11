import Foundation
import UIKit

protocol DashboardRouting {
    func routeToLogin()
}

class DashboardRouter: DashboardRouting {
    weak var dashboardViewController: DashboardViewController?

    func routeToLogin() {
//        let viewController = LoginViewController.newInstance()
//        dashboardViewController?.navigationController?.pushViewController(viewController, animated: true)
        dashboardViewController?.navigationController?.popToRootViewController(animated: true)
    }
}
