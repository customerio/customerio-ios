import UIKit
import UserNotifications

class SettingsViewController: UIViewController {
    static func newInstance() -> SettingsViewController {
        UIStoryboard.getViewController(identifier: "SettingsViewController")
    }
    
    // MARK: - Outlets
    @IBOutlet weak var deviceTokenTextField: ThemeTextField!
    @IBOutlet weak var apiKeyTextField: ThemeTextField!
    @IBOutlet weak var siteIdTextField: ThemeTextField!
    @IBOutlet weak var trackUrlTextField: ThemeTextField!
    @IBOutlet weak var trackDeviceToggle: UISwitch!
    @IBOutlet weak var debugModeToggle: UISwitch!
    @IBOutlet weak var trackScreenToggle: UISwitch!
    @IBOutlet weak var enablePushToggle: UISwitch!
    @IBOutlet weak var bgQMinTasks: ThemeTextField!
    @IBOutlet weak var bgQTakDelayTextField: ThemeTextField!
    
    var settingsRouter: SettingsRouting?
    var storage = DI.shared.storage
    var currentSettings : Settings!
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureSettingsRouter()
        getDefaultValues()
        setDefaultValues()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = false
    }
    
    func getDefaultValues() {
        currentSettings.deviceToken = storage.deviceToken ?? "Error"
        currentSettings.trackUrl = storage.trackUrl ?? "-"
        currentSettings.siteId = storage.siteId ?? Env.customerIOSiteId
        currentSettings.apiKey = storage.apiKey ?? Env.customerIOApiKey
        currentSettings.bgQDelay = storage.bgQDelay ?? "30"
        currentSettings.bgQMinTasks = storage.bgNumOfTasks ?? "10"
        currentSettings.isTrackScreenEnabled = storage.isTrackScreenEnabled ?? false
        currentSettings.isDebugModeEnabled = storage.isDebugModeEnabled ?? true
        currentSettings.isDeviceAttributeEnabled = storage.isTrackDeviceAttrEnabled ?? true
        getStatusOfPushPermissions { status in
            DispatchQueue.main.async {
                self.currentSettings?.isPushEnabled = status == .authorized ? true : false
            }
        }
    }
    
    func setDefaultValues() {
        deviceTokenTextField.text = currentSettings.deviceToken
        trackUrlTextField.text = currentSettings.trackUrl
        
        siteIdTextField.text = currentSettings.siteId
        apiKeyTextField.text = currentSettings.apiKey
        
        bgQTakDelayTextField.text = currentSettings.bgQDelay
        bgQMinTasks.text = currentSettings.bgQMinTasks
        
        trackScreenToggle.isOn = currentSettings.isTrackScreenEnabled
        trackDeviceToggle.isOn = currentSettings.isDeviceAttributeEnabled
        debugModeToggle.isOn = currentSettings.isDebugModeEnabled
        enablePushToggle.isOn = currentSettings.isPushEnabled
    }
    
    func configureSettingsRouter() {
        let router = SettingsRouter()
        settingsRouter = router
        router.settingsViewController = self
    }
    
    func popToSource() {
        settingsRouter?.routeToSource()
    }
    
    func getStatusOfPushPermissions(handler: @escaping(UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            handler(settings.authorizationStatus)
        }
    }
    
    // MARK: - Actions
    @IBAction func saveSettings(_ sender: UIButton) {
        showAlert(withMessage: "Settings saved. This will require an app restart to bring the changes in effect.", action: popToSource)
        
        
    }
}
