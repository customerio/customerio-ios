import Foundation
import UIKit

protocol LoginRouting {
    func routeToDashboard()
    func routeToSettings()
}

class LoginRouter: LoginRouting {
    weak var loginViewController: LoginViewController?

    func routeToDashboard() {
        let viewController = DashboardViewController.newInstance()
        loginViewController?.navigationController?.pushViewController(viewController, animated: true)
    }

    func routeToSettings() {
        // TODO: - Settings screen yet to be created
    }
}
