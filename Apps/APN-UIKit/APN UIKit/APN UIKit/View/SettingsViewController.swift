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
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureSettingsRouter()
        setDefaultValues()
    }
    
    override func viewWillAppear(_ animated: Bool) {
         super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = false
    }
    
    func setDefaultValues() {
        deviceTokenTextField.text = storage.deviceToken
        trackUrlTextField.text = "Yet to set"
        
        siteIdTextField.text = "Get from Env class"
        apiKeyTextField.text = "Get from Env class"
        
        bgQTakDelayTextField.text = "30" // update when saved in storage
        bgQMinTasks.text = "10"
        
        trackScreenToggle.isOn = false
        trackDeviceToggle.isOn = true
        debugModeToggle.isOn = true
        getStatusOfPushPermissions { status in
            if status == .authorized {
                DispatchQueue.main.async {
                    self.enablePushToggle.isOn = true
                }
            }
        }
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
