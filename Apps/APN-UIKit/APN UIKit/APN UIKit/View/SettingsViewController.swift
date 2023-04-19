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
    @IBOutlet weak var bgQMinTasksTextField: ThemeTextField!
    @IBOutlet weak var bgQTakDelayTextField: ThemeTextField!
    
    var notificationUtil = DI.shared.notificationUtil
    var settingsRouter: SettingsRouting?
    var storage = DI.shared.storage
    var currentSettings : Settings!
    
    var pushSwitchState:Bool {
        return enablePushToggle.isOn
    }
    
    var trackScreenState:Bool {
        return trackScreenToggle.isOn
    }
    
    var trackDeviceAttributeState:Bool {
        return trackDeviceToggle.isOn
    }
    
    var debugModeState: Bool {
        return debugModeToggle.isOn
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureSettingsRouter()
        getAndSetDefaultValues()
        addObserversForSettingsScreen()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = false
    }
    
    func addObserversForSettingsScreen() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(appMovedToForeground), name: UIApplication.willEnterForegroundNotification, object: nil)

    }
    
    @objc
    func appMovedToForeground() {
        getStatusOfPushPermissions { status in
            DispatchQueue.main.async {
                self.enablePushToggle.isOn = status == .authorized ? true : false
            }
        }
    }
    
    func getAndSetDefaultValues() {
        
        currentSettings = Settings(deviceToken: storage.deviceToken ?? "Error",
                                   trackUrl: storage.trackUrl ?? "-",
                                   siteId: storage.siteId ?? Env.customerIOSiteId,
                                   apiKey: storage.apiKey ?? Env.customerIOApiKey,
                                   bgQDelay: storage.bgQDelay ?? "30",
                                   bgQMinTasks: storage.bgNumOfTasks ?? "10",
                                   isPushEnabled: false,
                                   isTrackScreenEnabled: storage.isTrackScreenEnabled ?? false,
                                   isDeviceAttributeEnabled: storage.isTrackDeviceAttrEnabled ?? true,
                                   isDebugModeEnabled: storage.isDebugModeEnabled ?? true)
        
        getStatusOfPushPermissions { status in
            DispatchQueue.main.async {
                self.currentSettings?.isPushEnabled = status == .authorized ? true : false
                self.setDefaultValues()
            }
        }
    }
    
    func setDefaultValues() {
        deviceTokenTextField.text = currentSettings.deviceToken
        trackUrlTextField.text = currentSettings.trackUrl
        
        siteIdTextField.text = currentSettings.siteId
        apiKeyTextField.text = currentSettings.apiKey
        
        bgQTakDelayTextField.text = currentSettings.bgQDelay
        bgQMinTasksTextField.text = currentSettings.bgQMinTasks
        
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
    
    func compareAndSave() {
        
        // Track Url
        if currentSettings.trackUrl != trackUrlTextField.text {
            storage.trackUrl = trackUrlTextField.text
        }
        
        // Background Queue Seconds Delay
        if currentSettings.bgQDelay != bgQTakDelayTextField.text {
            storage.bgQDelay = bgQTakDelayTextField.text
        }
        
        // Min number of tasks
        if currentSettings.bgQMinTasks != bgQMinTasksTextField.text {
            storage.bgNumOfTasks = bgQMinTasksTextField.text
        }
        
        // Min tasks in queue
        if currentSettings.bgQMinTasks != bgQMinTasksTextField.text {
            storage.bgNumOfTasks = bgQMinTasksTextField.text
        }
        
        // Push enabled
        if currentSettings.isPushEnabled != pushSwitchState {
            storage.isPushEnabled = pushSwitchState
        }
        
        // Track screen enabled
        if currentSettings.isTrackScreenEnabled != trackScreenState{
            storage.isTrackScreenEnabled = trackScreenState
        }
        
        // Debug screen
        if currentSettings.isDebugModeEnabled != debugModeState {
            storage.isDebugModeEnabled = debugModeState
        }
    }
    
    
    // MARK: - Actions
    @IBAction func saveSettings(_ sender: UIButton) {
        compareAndSave()
        showAlert(withMessage: "Settings saved. This will require an app restart to bring the changes in effect.", action: popToSource)
    }
    
    
    @IBAction func enablePushChanged(_ sender: UISwitch) {
        
        getStatusOfPushPermissions { status in
            DispatchQueue.main.async {
                if status == .notDetermined {
                    self.notificationUtil.showPromptForPushPermission()
                }
                else {
                    if let appSettingsUrl = URL(string: UIApplication.openSettingsURLString) {
                       UIApplication.shared.open(appSettingsUrl)
                        sender.setOn(!sender.isOn, animated: true)
                     }
                }
            }
        }
    }
}
