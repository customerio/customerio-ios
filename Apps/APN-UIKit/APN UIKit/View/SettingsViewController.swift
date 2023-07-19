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
    @IBOutlet var apiKeyTextField: ThemeTextField!
    @IBOutlet var siteIdTextField: ThemeTextField!
    @IBOutlet var trackUrlTextField: ThemeTextField!
    @IBOutlet var trackDeviceToggle: UISwitch!
    @IBOutlet var debugModeToggle: UISwitch!
    @IBOutlet var trackScreenToggle: UISwitch!
    @IBOutlet var bgQMinTasksTextField: ThemeTextField!
    @IBOutlet var bgQTakDelayTextField: ThemeTextField!

    @IBOutlet var copyToClipboardImageView: UIImageView!
    @IBOutlet var clipboardView: UIView!
    var notificationUtil = DIGraph.shared.notificationUtil
    var settingsRouter: SettingsRouting?
    var storage = DIGraph.shared.storage
    var currentSettings: Settings!
    var deepLinkSiteId: String?
    var deepLinkApiKey: String?
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
        var apiKey = storage.apiKey ?? BuildEnvironment.CustomerIO.apiKey
        if let deepLinkSiteId = deepLinkSiteId, let deepLinkApiKey = deepLinkApiKey {
            siteId = deepLinkSiteId
            apiKey = deepLinkApiKey
        }
        currentSettings = Settings(
            deviceToken: storage.deviceToken ?? "Error",
            trackUrl: storage.trackUrl ?? "https://track-sdk.customer.io/",
            siteId: siteId,
            apiKey: apiKey,
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
        trackUrlTextField.text = currentSettings.trackUrl

        siteIdTextField.text = currentSettings.siteId
        apiKeyTextField.text = currentSettings.apiKey

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
        setAppiumAccessibilityIdTo(trackUrlTextField, value: "Track URL Input")
        setAppiumAccessibilityIdTo(siteIdTextField, value: "Site ID Input")
        setAppiumAccessibilityIdTo(apiKeyTextField, value: "API Key Input")
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
        // Track Url
        storage.trackUrl = trackUrlTextField.text
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
        // Api Key
        storage.apiKey = apiKeyTextField.text
    }

    func isValid() -> Bool {
        // Site id and Api Key
        if siteIdTextField.isTextTrimEmpty {
            showToast(withMessage: "Enter a valid value for Site Id.")
            return false
        }
        if apiKeyTextField.isTextTrimEmpty {
            showToast(withMessage: "Enter a valid value for Api Key.")
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
        // Tracking Url
        if let trackingUrl = trackUrlTextField.text {
            if trackUrlTextField.isTextTrimEmpty || trackingUrl.isValidUrl {
                showToast(withMessage: "Enter a valid value for CIO Track Url.")
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
            deviceToken: storage.deviceToken ?? "Error",
            trackUrl: "https://track-sdk.customer.io/",
            siteId: BuildEnvironment.CustomerIO.siteId,
            apiKey: BuildEnvironment.CustomerIO.apiKey,
            bgQDelay: "30",
            bgQMinTasks: "10",
            isTrackScreenEnabled: true,
            isDeviceAttributeEnabled: true,
            isDebugModeEnabled: true
        )
        setDefaultValues()
    }
}
