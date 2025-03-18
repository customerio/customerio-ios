import Foundation
import UIKit

protocol SettingsRouting {
    func routeToMainSettings()
    func routeToInternalSettings()
}

class SettingsRouter: SettingsRouting {
    weak var navigationController: UINavigationController?
    private var settingsViewModel: SettingsViewModel!
    
    init(navigationController: UINavigationController? = nil) {
        self.navigationController = navigationController
        settingsViewModel = SettingsViewModel(settingRouter: self)
    }
    
    func routeToMainSettings() {
        let mainSettingsViewController = MainSettingsViewController.newInstance()
        mainSettingsViewController.settingsViewModel = settingsViewModel
        navigationController?.pushViewController(mainSettingsViewController, animated: true)
    }
    
    func routeToInternalSettings() {
        let internalSettingsViewController = InternalSettingsViewController.newInstance()
        internalSettingsViewController.settingsViewModel = settingsViewModel
        navigationController?.pushViewController(internalSettingsViewController, animated: true)
    }
}
