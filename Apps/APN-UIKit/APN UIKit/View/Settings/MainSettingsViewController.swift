import CioDataPipelines
import UIKit
import UserNotifications

enum BooleanSettingType: Int {
    case autoTrackDeviceAttributes = 1
    case autoTrackUIKitScreenViews = 2
    case trackApplicationLifecycleEvents = 3
    case screenViewUse = 4
    case autoFetchDeviceToken = 5
    case autoTrackPushEvents = 6
    case showPushAppInForeground = 7
}

class MainSettingsViewController: BaseViewController {
    static func newInstance() -> MainSettingsViewController {
        UIStoryboard.getViewController(identifier: "MainSettingsViewController")
    }

    var settingsViewModel: SettingsViewModel!
    private let screenName = "settings"

    // MARK: - Outlets

    @IBOutlet var cdpApiKeyTextField: ThemeTextField!
    @IBOutlet var siteIdTextField: ThemeTextField!

    @IBOutlet var regionUSButton: UIButton!
    @IBOutlet var regionEUButton: UIButton!

    @IBOutlet var autoTrackDeviceAttributesTrueButton: UIButton!
    @IBOutlet var autoTrackDeviceAttributesFalseButton: UIButton!

    @IBOutlet var autoTrackUIKitScreenViewTrueButton: UIButton!
    @IBOutlet var autoTrackUIKitScreenViewFalseButton: UIButton!

    @IBOutlet var trackApplicationLifecycleEventsTrueButton: UIButton!
    @IBOutlet var trackApplicationLifecycleEventsFalseButton: UIButton!

    @IBOutlet var screenViewUseAllButton: UIButton!
    @IBOutlet var screenViewUseInAppButton: UIButton!

    @IBOutlet var logLevelErrorButton: UIButton!
    @IBOutlet var logLevelInfoButton: UIButton!
    @IBOutlet var logLevelDebugButton: UIButton!

    @IBOutlet var autoFetchDeviceTokenTrueButton: UIButton!
    @IBOutlet var autoFetchDeviceTokenFalseButton: UIButton!

    @IBOutlet var autoTrackPushEventsTrueButton: UIButton!
    @IBOutlet var autoTrackPushEventsFalseButton: UIButton!

    @IBOutlet var showPushAppInForegroundTrueButton: UIButton!
    @IBOutlet var showPushAppInForegroundFalseButton: UIButton!

    @IBOutlet var inAppSiteIdTextField: UITextField!
    @IBOutlet var inAppRegionUSButton: UIButton!
    @IBOutlet var inAppRegionEUButton: UIButton!

    @IBOutlet var screenNameLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()

        assert(settingsViewModel != nil, "ViewModel must be set before using MainSettingsViewController")

        title = "Settings"
        screenNameLabel.text = screenName

        configureButtonActions()
        setInitialValues()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = false

        CustomerIO.shared.screen(title: screenName, properties: [:])
    }

    private func setInitialValues() {
        setDataPipelineInitialValues()
        setMessagingPushAPNInitialValues()
        setMessagingInAppInitialValues()
    }

    private func setDataPipelineInitialValues() {
        cdpApiKeyTextField.text = settingsViewModel.settings.dataPipelines.cdpApiKey
        siteIdTextField.text = settingsViewModel.settings.dataPipelines.siteId

        // Region
        regionUSButton.isSelected = settingsViewModel.settings.dataPipelines.region == .US
        regionEUButton.isSelected = settingsViewModel.settings.dataPipelines.region == .EU

        // Auto Track Device Attributes
        autoTrackDeviceAttributesTrueButton.isSelected = settingsViewModel.settings.dataPipelines.autoTrackDeviceAttributes
        autoTrackDeviceAttributesFalseButton.isSelected = !settingsViewModel.settings.dataPipelines.autoTrackDeviceAttributes

        // Auto Track UIKit Screen Views
        autoTrackUIKitScreenViewTrueButton.isSelected = settingsViewModel.settings.dataPipelines.autoTrackUIKitScreenViews
        autoTrackUIKitScreenViewFalseButton.isSelected = !settingsViewModel.settings.dataPipelines.autoTrackUIKitScreenViews

        // Track Application Lifecycle Events
        trackApplicationLifecycleEventsTrueButton.isSelected = settingsViewModel.settings.dataPipelines.trackApplicationLifecycleEvents
        trackApplicationLifecycleEventsFalseButton.isSelected = !settingsViewModel.settings.dataPipelines.trackApplicationLifecycleEvents

        // Screen View Use
        screenViewUseAllButton.isSelected = settingsViewModel.settings.dataPipelines.screenViewUse == .All
        screenViewUseInAppButton.isSelected = settingsViewModel.settings.dataPipelines.screenViewUse == .InApp

        // Log Level
        logLevelErrorButton.isSelected = settingsViewModel.settings.dataPipelines.logLevel == .Error
        logLevelInfoButton.isSelected = settingsViewModel.settings.dataPipelines.logLevel == .Info
        logLevelDebugButton.isSelected = settingsViewModel.settings.dataPipelines.logLevel == .Debug
    }

    private func setMessagingPushAPNInitialValues() {
        // Auto Fetch Device Token
        autoFetchDeviceTokenTrueButton.isSelected = settingsViewModel.settings.messaging.autoFetchDeviceToken
        autoFetchDeviceTokenFalseButton.isSelected = !settingsViewModel.settings.messaging.autoFetchDeviceToken

        // Auto Track Push Events
        autoTrackPushEventsTrueButton.isSelected = settingsViewModel.settings.messaging.autoTrackPushEvents
        autoTrackPushEventsFalseButton.isSelected = !settingsViewModel.settings.messaging.autoTrackPushEvents

        // Show Push App In Foreground
        showPushAppInForegroundTrueButton.isSelected = settingsViewModel.settings.messaging.showPushAppInForeground
        showPushAppInForegroundFalseButton.isSelected = !settingsViewModel.settings.messaging.showPushAppInForeground
    }

    private func setMessagingInAppInitialValues() {
        // Site ID
        inAppSiteIdTextField.text = settingsViewModel.settings.dataPipelines.siteId

        // In-App Region
        inAppRegionUSButton.isSelected = settingsViewModel.settings.inApp.region == .US
        inAppRegionEUButton.isSelected = settingsViewModel.settings.inApp.region == .EU
    }

    private func configureButtonActions() {
        configureDataPipelineButtonActions()
        configureMessagingPushAPNButtonActions()
        configureMessagingInAppButtonActions()
    }

    private func configureDataPipelineButtonActions() {
        configureRegionButtons()
        configureBooleanButtons()
        configureLogLevelButtons()
    }

    private func configureRegionButtons() {
        regionUSButton.addTarget(self, action: #selector(regionButtonTapped(_:)), for: .touchUpInside)
        regionEUButton.addTarget(self, action: #selector(regionButtonTapped(_:)), for: .touchUpInside)
    }

    private func configureBooleanButtons() {
        configureBooleanButtonPair(autoTrackDeviceAttributesTrueButton, autoTrackDeviceAttributesFalseButton, type: .autoTrackDeviceAttributes)
        configureBooleanButtonPair(autoTrackUIKitScreenViewTrueButton, autoTrackUIKitScreenViewFalseButton, type: .autoTrackUIKitScreenViews)
        configureBooleanButtonPair(trackApplicationLifecycleEventsTrueButton, trackApplicationLifecycleEventsFalseButton, type: .trackApplicationLifecycleEvents)
        configureBooleanButtonPair(screenViewUseAllButton, screenViewUseInAppButton, type: .screenViewUse)
    }

    private func configureLogLevelButtons() {
        logLevelErrorButton.addTarget(self, action: #selector(logLevelButtonTapped(_:)), for: .touchUpInside)
        logLevelInfoButton.addTarget(self, action: #selector(logLevelButtonTapped(_:)), for: .touchUpInside)
        logLevelDebugButton.addTarget(self, action: #selector(logLevelButtonTapped(_:)), for: .touchUpInside)
    }

    private func configureBooleanButtonPair(_ trueButton: UIButton, _ falseButton: UIButton, type: BooleanSettingType) {
        trueButton.addTarget(self, action: #selector(booleanButtonTapped(_:)), for: .touchUpInside)
        falseButton.addTarget(self, action: #selector(booleanButtonTapped(_:)), for: .touchUpInside)
        trueButton.tag = type.rawValue
        falseButton.tag = type.rawValue
    }

    private func configureMessagingPushAPNButtonActions() {
        configureBooleanButtonPair(autoFetchDeviceTokenTrueButton, autoFetchDeviceTokenFalseButton, type: .autoFetchDeviceToken)
        configureBooleanButtonPair(autoTrackPushEventsTrueButton, autoTrackPushEventsFalseButton, type: .autoTrackPushEvents)
        configureBooleanButtonPair(showPushAppInForegroundTrueButton, showPushAppInForegroundFalseButton, type: .showPushAppInForeground)
    }

    private func configureMessagingInAppButtonActions() {
        inAppRegionUSButton.addTarget(self, action: #selector(inAppRegionButtonTapped(_:)), for: .touchUpInside)
        inAppRegionEUButton.addTarget(self, action: #selector(inAppRegionButtonTapped(_:)), for: .touchUpInside)
    }

    private func updateRegion(_ value: Region) {
        settingsViewModel.regionUpdated(value)
        setInitialValues()
    }

    private func updateAutoTrackDeviceAttributes(_ value: Bool) {
        settingsViewModel.autoTrackDeviceAttributesUpdated(value)
        setInitialValues()
    }

    private func updateAutoTrackUIKitScreenViews(_ value: Bool) {
        settingsViewModel.autoTrackUIKitScreenViewsUpdated(value)
        setInitialValues()
    }

    private func updateTrackApplicationLifecycleEvents(_ value: Bool) {
        settingsViewModel.trackApplicationLifecycleEventsUpdated(value)
        setInitialValues()
    }

    private func updateScreenViewUse(_ value: ScreenViewUse) {
        settingsViewModel.screenViewUseUpdted(value)
        setInitialValues()
    }

    private func updateLogLevel(_ value: LogLevel) {
        settingsViewModel.logLevelUpdated(value)
        setInitialValues()
    }

    private func updateAutoFetchDeviceToken(_ value: Bool) {
        settingsViewModel.autoFetchDeviceTokenUpdated(value)
        setInitialValues()
    }

    private func updateAutoTrackPushEvents(_ value: Bool) {
        settingsViewModel.autoTrackPushEventsUpdated(value)
        setInitialValues()
    }

    private func updateShowPushAppInForeground(_ value: Bool) {
        settingsViewModel.showPushAppInForegroundUpdated(value)
        setInitialValues()
    }

    private func updateInAppRegion(_ value: Region) {
        settingsViewModel.inAppRegionUpdated(value)
        setInitialValues()
    }

    // MARK: - Generic Action Methods

    @objc private func regionButtonTapped(_ sender: UIButton) {
        let region: Region = sender == regionUSButton ? .US : .EU
        updateRegion(region)
    }

    @objc private func booleanButtonTapped(_ sender: UIButton) {
        guard let settingType = BooleanSettingType(rawValue: sender.tag) else { return }

        let isTrueButton = sender.titleLabel?.text?.contains("True") == true ||
            sender.titleLabel?.text?.contains("All") == true

        switch settingType {
        case .autoTrackDeviceAttributes:
            updateAutoTrackDeviceAttributes(isTrueButton)
        case .autoTrackUIKitScreenViews:
            updateAutoTrackUIKitScreenViews(isTrueButton)
        case .trackApplicationLifecycleEvents:
            updateTrackApplicationLifecycleEvents(isTrueButton)
        case .screenViewUse:
            updateScreenViewUse(isTrueButton ? .All : .InApp)
        case .autoFetchDeviceToken:
            updateAutoFetchDeviceToken(isTrueButton)
        case .autoTrackPushEvents:
            updateAutoTrackPushEvents(isTrueButton)
        case .showPushAppInForeground:
            updateShowPushAppInForeground(isTrueButton)
        }
    }

    @objc private func logLevelButtonTapped(_ sender: UIButton) {
        let logLevel: LogLevel
        switch sender {
        case logLevelErrorButton: logLevel = .Error
        case logLevelInfoButton: logLevel = .Info
        case logLevelDebugButton: logLevel = .Debug
        default: return
        }
        updateLogLevel(logLevel)
    }

    @objc private func inAppRegionButtonTapped(_ sender: UIButton) {
        let region: Region = sender == inAppRegionUSButton ? .US : .EU
        updateInAppRegion(region)
    }

    // MARK: - Actions

    @IBAction func saveChanges(_ sender: UIBarButtonItem) {
        showSavingAlertAndExecuteDefaultAction(saveButtonTitle: "Save and close") { [weak self] in
            self?.settingsViewModel.saveSettings()
        }
    }

    @IBAction func cdpApiKeyChanged(_ sender: UITextField) {
        settingsViewModel.cdpApiKeyUpdated(sender.text ?? "")
    }

    @IBAction func siteIdChanged(_ sender: UITextField) {
        settingsViewModel.sideIdUpdated(sender.text ?? "")
    }

    @IBAction func inAppSiteIdChanged(_ sender: UITextField) {
        settingsViewModel.inAppSideIdUpdated(sender.text ?? "")
    }

    @IBAction func restoreDefaultSettings(_ sender: UIButton) {
        showSavingAlertAndExecuteDefaultAction(saveButtonTitle: "Restore and close") { [weak self] in
            self?.settingsViewModel.restoreDefaultSettings()
        }
    }

    @IBAction func internalSettingsButtonTapped(_ sender: Any) {
        settingsViewModel.internalSettingsScreenRequested()
    }

    // MARK: Private methods

    private func showSavingAlertAndExecuteDefaultAction(
        saveButtonTitle: String,
        completion: @escaping (() -> Void)
    ) {
        let alertController = UIAlertController(
            title: "Update settings",
            message: "App will be closed automatically after saving. It must be reopened manually afterwards.",
            preferredStyle: .alert
        )

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        alertController.addAction(cancelAction)

        let saveAction = UIAlertAction(title: saveButtonTitle, style: .default) { _ in
            completion()
            // It's ok to have `exit(0)` since app is not intended for the App Store.
            // Delay is added to ensure UserDefaults sync is complete.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                exit(0)
            }
        }
        alertController.addAction(saveAction)

        present(alertController, animated: true)
    }
}
