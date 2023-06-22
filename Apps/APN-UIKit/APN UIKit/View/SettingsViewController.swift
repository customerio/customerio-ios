import UIKit
import UserNotifications

class SettingsViewController: BaseViewController {
    static func newInstance() -> SettingsViewController {
        UIStoryboard.getViewController(identifier: "SettingsViewController")
    }

    // MARK: - Outlets

    @IBOutlet var deviceTokenTextField: ThemeTextField!
    @IBOutlet var apiKeyTextField: ThemeTextField!
    @IBOutlet var siteIdTextField: ThemeTextField!
    @IBOutlet var trackUrlTextField: ThemeTextField!
    @IBOutlet var trackDeviceToggle: UISwitch!
    @IBOutlet var debugModeToggle: UISwitch!
    @IBOutlet var trackScreenToggle: UISwitch!
    @IBOutlet var enablePushToggle: UISwitch!
    @IBOutlet var bgQMinTasksTextField: ThemeTextField!
    @IBOutlet var bgQTakDelayTextField: ThemeTextField!

    @IBOutlet var copyToClipboardImageView: UIImageView!
    @IBOutlet var clipboardView: UIView!
    var notificationUtil = DIGraph.shared.notificationUtil
    var settingsRouter: SettingsRouting?
    var storage = DIGraph.shared.storage
    var currentSettings: Settings!

    var pushSwitchState: Bool {
        enablePushToggle.isOn
    }

    var trackScreenState: Bool {
        trackScreenToggle.isOn
    }

    var trackDeviceAttributeState: Bool {
        trackDeviceToggle.isOn
    }

    var debugModeState: Bool {
        debugModeToggle.isOn
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureClipboardImageView()
        configureSettingsRouter()
        getAndSetDefaultValues()
        addObserversForSettingsScreen()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = false
    }

    func addObserversForSettingsScreen() {
        NotificationCenter.default.addObserver(self, selector: #selector(appMovedToForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc
    func appMovedToForeground() {
        getStatusOfPushPermissions { status in
            DispatchQueue.main.async {
                self.enablePushToggle.isOn = status == .authorized ? true : false
            }
        }
    }

    func configureClipboardImageView() {
        copyToClipboardImageView.addTapGesture(onTarget: self, #selector(SettingsViewController.copyToClipboard))
    }

    @objc
    func copyToClipboard() {
        UIPasteboard.general.string = deviceTokenTextField.text ?? ""

        showAlert(withMessage: "Copied to clipboard")
    }

    func getAndSetDefaultValues() {
        
        currentSettings = Settings(
            deviceToken: storage.deviceToken ?? "Error",
            trackUrl: storage.trackUrl ?? "https://track-sdk.customer.io/",
            siteId: storage.siteId ?? BuildEnvironment.CustomerIO.siteId,
            apiKey: storage.apiKey ?? BuildEnvironment.CustomerIO.apiKey,
            bgQDelay: storage.bgQDelay ?? "30",
            bgQMinTasks: storage.bgNumOfTasks ?? "10",
            isPushEnabled: false,
            isTrackScreenEnabled: storage.isTrackScreenEnabled ?? true,
            isDeviceAttributeEnabled: storage.isTrackDeviceAttrEnabled ?? true,
            isDebugModeEnabled: storage.isDebugModeEnabled ?? true
        )
        
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

    func getStatusOfPushPermissions(handler: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            handler(settings.authorizationStatus)
        }
    }

    func save() {
        // Track Url
        storage.trackUrl = trackUrlTextField.text
        // Background Queue Seconds Delay
        storage.bgQDelay = bgQTakDelayTextField.text
        // Min number of tasks
        storage.bgNumOfTasks = bgQMinTasksTextField.text
        // Push enabled
        storage.isPushEnabled = pushSwitchState
        // Track screen enabled
        storage.isTrackScreenEnabled = trackScreenState
        // Debug screen
        storage.isDebugModeEnabled = debugModeState
        // SiteId
        storage.siteId = siteIdTextField.text
        // Api Key
        storage.apiKey = siteIdTextField.text
    }
    
    func isValid() -> Bool {
        // Site id and Api Key
        if siteIdTextField.isTextTrimEmpty {
            showAlert(withMessage: "Enter a valid value for Site Id.")
            return false
        }
        if apiKeyTextField.isTextTrimEmpty {
            showAlert(withMessage: "Enter a valid value for Api Key.")
            return false
        }
        // BGQ
        if bgQMinTasksTextField.isTextTrimEmpty || bgQMinTasksTextField.text == "0" {
            showAlert(withMessage: "Enter a valid value for Background Queue Minimum number of tasks.")
            return false
        }
        if bgQTakDelayTextField.isTextTrimEmpty || bgQTakDelayTextField.text == "0" {
            showAlert(withMessage: "Enter a valid value for Background Queue Delay in seconds.")
            return false
        }
        // Tracking Url
        if let trackingUrl = trackUrlTextField.text {
            if trackUrlTextField.isTextTrimEmpty || trackingUrl.isValidUrl {
                showAlert(withMessage: "Enter a valid value for CIO Track Url.")
                return false
            }
        }
        return true
    }
    
    func isValidUrl(_ urlString: String?) -> Bool {
        if let urlString = urlString {
            if let url = NSURL(string: urlString) {
                return UIApplication.shared.canOpenURL(url as URL)
            }
        }
        return false
    }

    // MARK: - Actions

    @IBAction func saveSettings(_ sender: UIButton) {
        save()
        showAlert(withMessage: "Settings saved. This will require an app restart to bring the changes in effect.", action: popToSource)
    }

    @IBAction func enablePushChanged(_ sender: UISwitch) {
        getStatusOfPushPermissions { status in
            DispatchQueue.main.async {
                if status == .notDetermined {
                    self.notificationUtil.showPromptForPushPermission { status in
                        
                        DispatchQueue.main.async {
                            sender.setOn(status, animated: true)
                        }
                    }
                } else {
                    if let appSettingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(appSettingsUrl)
                        sender.setOn(!sender.isOn, animated: true)
                    }
                }
            }
        }
    }
}
