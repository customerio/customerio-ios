import Foundation
import UIKit

protocol SettingsRouting {
    func routeToSource()
}

class SettingsRouter: SettingsRouting {
    weak var settingsViewController: SettingsViewController?

    func routeToSource() {
        settingsViewController?.navigationController?.popViewController(animated: true)
    }
}
