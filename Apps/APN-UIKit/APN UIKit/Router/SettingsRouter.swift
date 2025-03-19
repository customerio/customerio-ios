import Foundation
import UIKit

protocol SettingsRouting {
    func routeToMainSettings(siteIdOverride: String?, cdpApiKeyOverride: String?)
    func routeToInternalSettings()
}

class SettingsRouter: SettingsRouting {
    weak var navigationController: UINavigationController?
    private var settingsViewModel: SettingsViewModel?
    
    init(navigationController: UINavigationController? = nil) {
        self.navigationController = navigationController
    }
    
    func routeToMainSettings(siteIdOverride: String?, cdpApiKeyOverride: String?) {
        settingsViewModel = SettingsViewModel(settingRouter: self)
        settingsViewModel?.overrideSiteIdAndCdpApiKey(siteIdOverride: siteIdOverride, cdpApiKeyOverride: cdpApiKeyOverride)
        
        let mainSettingsViewController = MainSettingsViewController.newInstance()
        mainSettingsViewController.settingsViewModel = settingsViewModel
        navigationController?.pushViewController(mainSettingsViewController, animated: true)
    }
    
    func routeToInternalSettings() {
        guard let settingsViewModel else { return }
        
        let internalSettingsViewController = InternalSettingsViewController.newInstance()
        internalSettingsViewController.settingsViewModel = settingsViewModel
        navigationController?.pushViewController(internalSettingsViewController, animated: true)
    }
}
