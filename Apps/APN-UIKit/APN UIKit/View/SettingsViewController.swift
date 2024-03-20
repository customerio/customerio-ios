import CioDataPipelines
import UIKit
import UserNotifications

class SettingsViewController: BaseViewController {
    static func newInstance() -> SettingsViewController {
        UIStoryboard.getViewController(identifier: "SettingsViewController")
    }

    // MARK: - Outlets

    @IBOutlet var restoreDefaultButton: UIButton!
    @IBOutlet var saveButton: ThemeButton!
    @IBOutlet var deviceTokenTextField: ThemeTextField!

    @IBOutlet var cdpApiKeyTextField: ThemeTextField!
    @IBOutlet var siteIdTextField: ThemeTextField!
    @IBOutlet var trackDeviceToggle: UISwitch!
    @IBOutlet var debugModeToggle: UISwitch!
    @IBOutlet var trackScreenToggle: UISwitch!
    @IBOutlet var bgQMinTasksTextField: ThemeTextField!
    @IBOutlet var bgQTakDelayTextField: ThemeTextField!
    @IBOutlet var apiHostTextField: ThemeTextField!
    @IBOutlet var cdnHostTextField: ThemeTextField!
    @IBOutlet var copyToClipboardImageView: UIImageView!
    @IBOutlet var clipboardView: UIView!
    var notificationUtil = DIGraphShared.shared.notificationUtil
    var settingsRouter: SettingsRouting?
    var storage = DIGraphShared.shared.storage
    var currentSettings: Settings!
    var deepLinkSiteId: String?
    var deeplinkCdpApiKey: String?
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
        addAccessibilityIdentifiersForAppium()
        configureClipboardImageView()
        configureSettingsRouter()
        getAndSetDefaultValues()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = false
    }

    func configureClipboardImageView() {
        copyToClipboardImageView.addTapGesture(onTarget: self, #selector(SettingsViewController.copyToClipboard))
    }

    @objc
    func copyToClipboard() {
        UIPasteboard.general.string = deviceTokenTextField.text ?? ""

        showToast(withMessage: "Copied to clipboard")
    }

    func getAndSetDefaultValues() {
        var siteId = storage.siteId ?? BuildEnvironment.CustomerIO.siteId
        var cdpApiKey = storage.cdpApiKey ?? BuildEnvironment.CustomerIO.cdpApiKey
        if let deepLinkSiteId = deepLinkSiteId, let deeplinkCdpApiKey = deeplinkCdpApiKey {
            siteId = deepLinkSiteId
            cdpApiKey = deeplinkCdpApiKey
        }
        currentSettings = Settings(
            deviceToken: CustomerIO.shared.registeredDeviceToken ?? "Error",
            cdnHost: storage.cdnHost ?? "cdp.customer.io/v1",
            apiHost: storage.apiHost ?? "cdp.customer.io/v1",
            siteId: siteId,
            cdpApiKey: cdpApiKey,
            bgQDelay: storage.bgQDelay ?? "30",
            bgQMinTasks: storage.bgNumOfTasks ?? "10",
            isTrackScreenEnabled: storage.isTrackScreenEnabled ?? true,
            isDeviceAttributeEnabled: storage.isTrackDeviceAttrEnabled ?? true,
            isDebugModeEnabled: storage.isDebugModeEnabled ?? true
        )
        setDefaultValues()
    }

    func setDefaultValues() {
        deviceTokenTextField.text = currentSettings.deviceToken
        cdnHostTextField.text = currentSettings.cdnHost
        apiHostTextField.text = currentSettings.apiHost

        siteIdTextField.text = currentSettings.siteId
        cdpApiKeyTextField.text = currentSettings.cdpApiKey

        bgQTakDelayTextField.text = currentSettings.bgQDelay
        bgQMinTasksTextField.text = currentSettings.bgQMinTasks

        trackScreenToggle.isOn = currentSettings.isTrackScreenEnabled
        trackDeviceToggle.isOn = currentSettings.isDeviceAttributeEnabled
        debugModeToggle.isOn = currentSettings.isDebugModeEnabled
    }

    func configureSettingsRouter() {
        let router = SettingsRouter()
        settingsRouter = router
        router.settingsViewController = self
    }

    func popToSource() {
        settingsRouter?.routeToSource()
    }

    func addAccessibilityIdentifiersForAppium() {
        setAppiumAccessibilityIdTo(cdnHostTextField, value: "CDN Host Input")
        setAppiumAccessibilityIdTo(apiHostTextField, value: "API Host Input")
        setAppiumAccessibilityIdTo(siteIdTextField, value: "Site ID Input")
        setAppiumAccessibilityIdTo(cdpApiKeyTextField, value: "CDP API Key Input")
        setAppiumAccessibilityIdTo(trackScreenToggle, value: "Track Screens Toggle")
        setAppiumAccessibilityIdTo(trackDeviceToggle, value: "Track Device Attributes Toggle")
        setAppiumAccessibilityIdTo(debugModeToggle, value: "Debug Mode Toggle")
        setAppiumAccessibilityIdTo(saveButton, value: "Save Settings Button")
        setAppiumAccessibilityIdTo(restoreDefaultButton, value: "Restore Default Settings Button")
        let backButton = UIBarButtonItem()
        backButton.accessibilityIdentifier = "Back Button"
        backButton.isAccessibilityElement = true
        navigationController?.navigationBar.topItem?.backBarButtonItem = backButton
    }

    func getStatusOfPushPermissions(handler: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            handler(settings.authorizationStatus)
        }
    }

    func save() {
        // CDN Host
        storage.cdnHost = cdnHostTextField.text
        // API Host
        storage.apiHost = apiHostTextField.text
        // Background Queue Seconds Delay
        storage.bgQDelay = bgQTakDelayTextField.text
        // Min number of tasks
        storage.bgNumOfTasks = bgQMinTasksTextField.text
        // Track screen enabled
        storage.isTrackScreenEnabled = trackScreenState
        // Device attributes
        storage.isTrackDeviceAttrEnabled = trackDeviceAttributeState
        // Debug screen
        storage.isDebugModeEnabled = debugModeState
        // SiteId
        storage.siteId = siteIdTextField.text
        // CDP API Key
        storage.cdpApiKey = cdpApiKeyTextField.text
    }

    func isValid() -> Bool {
        // Site id and CDP API Key
        if siteIdTextField.isTextTrimEmpty {
            showToast(withMessage: "Enter a valid value for Site Id.")
            return false
        }
        if cdpApiKeyTextField.isTextTrimEmpty {
            showToast(withMessage: "Enter a valid value for CDP API Key.")
            return false
        }
        // BGQ
        if bgQMinTasksTextField.isTextTrimEmpty || bgQMinTasksTextField.text == "0" {
            showToast(withMessage: "Enter a valid value for Background Queue Minimum number of tasks.")
            return false
        }
        if bgQTakDelayTextField.isTextTrimEmpty || bgQTakDelayTextField.text == "0" {
            showToast(withMessage: "Enter a valid value for Background Queue Delay in seconds.")
            return false
        }
        // CDN Host
        if let cdnHost = cdnHostTextField.text {
            if cdnHostTextField.isTextTrimEmpty || cdnHost.isValidUrl {
                showToast(withMessage: "Enter a valid value for CDN Host.")
                return false
            }
        }
        // API Host
        if let apiHost = apiHostTextField.text {
            if apiHostTextField.isTextTrimEmpty || apiHost.isValidUrl {
                showToast(withMessage: "Enter a valid value for API Host.")
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
        showToast(withMessage: "Settings saved. This will require an app restart to bring the changes in effect.", action: popToSource)
    }

    @IBAction func restoreDefaultSettings(_ sender: UIButton) {
        currentSettings = Settings(
            deviceToken: CustomerIO.shared.registeredDeviceToken ?? "Error",
            cdnHost: "",
            apiHost: "",
            siteId: BuildEnvironment.CustomerIO.siteId,
            cdpApiKey: BuildEnvironment.CustomerIO.cdpApiKey,
            bgQDelay: "30",
            bgQMinTasks: "10",
            isTrackScreenEnabled: true,
            isDeviceAttributeEnabled: true,
            isDebugModeEnabled: true
        )
        setDefaultValues()
    }
}
