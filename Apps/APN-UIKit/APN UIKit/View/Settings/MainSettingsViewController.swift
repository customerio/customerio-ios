import CioDataPipelines
import UIKit
import UserNotifications

class MainSettingsViewController: BaseViewController {
    static func newInstance() -> MainSettingsViewController {
        UIStoryboard.getViewController(identifier: "MainSettingsViewController")
    }
    
    var settingsViewModel: SettingsViewModel!
    private let screenName = "settings"

    // MARK: - Outlets

    @IBOutlet weak var cdpApiKeyTextField: ThemeTextField!
    @IBOutlet weak var siteIdTextField: ThemeTextField!
    
    @IBOutlet weak var regionUSButton: UIButton!
    @IBOutlet weak var regionEUButton: UIButton!
    
    @IBOutlet weak var autoTrackDeviceAttributesTrueButton: UIButton!
    @IBOutlet weak var autoTrackDeviceAttributesFalseButton: UIButton!
    
    @IBOutlet weak var autoTrackUIKitScreenViewTrueButton: UIButton!
    @IBOutlet weak var autoTrackUIKitScreenViewFalseButton: UIButton!

    @IBOutlet weak var trackApplicationLifecycleEventsTrueButton: UIButton!
    @IBOutlet weak var trackApplicationLifecycleEventsFalseButton: UIButton!
    
    @IBOutlet weak var screenViewUseAllButton: UIButton!
    @IBOutlet weak var screenViewUseInAppButton: UIButton!
    
    @IBOutlet weak var logLevelErrorButton: UIButton!
    @IBOutlet weak var logLevelInfoButton: UIButton!
    @IBOutlet weak var logLevelDebugButton: UIButton!
    
    @IBOutlet weak var autoFetchDeviceTokenTrueButton: UIButton!
    @IBOutlet weak var autoFetchDeviceTokenFalseButton: UIButton!

    @IBOutlet weak var autoTrackPushEventsTrueButton: UIButton!
    @IBOutlet weak var autoTrackPushEventsFalseButton: UIButton!
    
    @IBOutlet weak var showPushAppInForegroundTrueButton: UIButton!
    @IBOutlet weak var showPushAppInForegroundFalseButton: UIButton!
    
    @IBOutlet weak var inAppSiteIdTextField: UITextField!
    @IBOutlet weak var inAppRegionUSButton: UIButton!
    @IBOutlet weak var inAppRegionEUButton: UIButton!
    
    @IBOutlet weak var screenNameLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        assert(settingsViewModel != nil, "ViewModel must be set before using MainSettingsViewController")
        
        self.title = "Settings"
        screenNameLabel.text = screenName

        configureButtonActions()
        setInitialValues()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = false
        
        CustomerIO.shared.screen(title: screenName, properties: [:])
    }
    
    func setInitialValues() {
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
        
        // Auto Fetch Device Token
        autoFetchDeviceTokenTrueButton.isSelected = settingsViewModel.settings.messaging.autoFetchDeviceToken
        autoFetchDeviceTokenFalseButton.isSelected = !settingsViewModel.settings.messaging.autoFetchDeviceToken
        
        // Auto Track Push Events
        autoTrackPushEventsTrueButton.isSelected = settingsViewModel.settings.messaging.autoTrackPushEvents
        autoTrackPushEventsFalseButton.isSelected = !settingsViewModel.settings.messaging.autoTrackPushEvents
        
        // Show Push App In Foreground
        showPushAppInForegroundTrueButton.isSelected = settingsViewModel.settings.messaging.showPushAppInForeground
        showPushAppInForegroundFalseButton.isSelected = !settingsViewModel.settings.messaging.showPushAppInForeground
        
        // Site ID
        inAppSiteIdTextField.text = settingsViewModel.settings.dataPipelines.siteId
        
        // In-App Region
        inAppRegionUSButton.isSelected = settingsViewModel.settings.inApp.region == .US
        inAppRegionEUButton.isSelected = settingsViewModel.settings.inApp.region == .EU
    }
    
    func configureButtonActions() {
        // region
        regionUSButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateRegion(.US)
        }), for:.touchUpInside)
        regionEUButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateRegion(.EU)
        }), for:.touchUpInside)
        
        // autoTrackDeviceAttributes
        autoTrackDeviceAttributesTrueButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateAutoTrackDeviceAttributes(true)
        }), for:.touchUpInside)
        autoTrackDeviceAttributesFalseButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateAutoTrackDeviceAttributes(false)
        }), for:.touchUpInside)
        
        // autoTrackUIKitScreenView
        autoTrackUIKitScreenViewTrueButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateAutoTrackUIKitScreenViews(true)
        }), for:.touchUpInside)
        autoTrackUIKitScreenViewFalseButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateAutoTrackUIKitScreenViews(false)
        }), for:.touchUpInside)
        
        // trackApplicationLifecycleEvents
        trackApplicationLifecycleEventsTrueButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateTrackApplicationLifecycleEvents(true)
        }), for:.touchUpInside)
        trackApplicationLifecycleEventsFalseButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateTrackApplicationLifecycleEvents(false)
        }), for:.touchUpInside)

        // screenViewUse
        screenViewUseAllButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateScreenViewUse(.All)
        }), for:.touchUpInside)
        screenViewUseInAppButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateScreenViewUse(.InApp)
        }), for:.touchUpInside)
        
        // logLevel
        logLevelErrorButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateLogLevel(.Error)
        }), for:.touchUpInside)
        logLevelInfoButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateLogLevel(.Info)
        }), for:.touchUpInside)
        logLevelDebugButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateLogLevel(.Debug)
        }), for:.touchUpInside)

        // autoFetchDeviceToken
        autoFetchDeviceTokenTrueButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateAutoFetchDeviceToken(true)
        }), for:.touchUpInside)
        autoFetchDeviceTokenFalseButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateAutoFetchDeviceToken(false)
        }), for:.touchUpInside)
        
        // autoTrackPushEvents
        autoTrackPushEventsTrueButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateAutoTrackPushEvents(true)
        }), for:.touchUpInside)
        autoTrackPushEventsFalseButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateAutoTrackPushEvents(false)
        }), for:.touchUpInside)
        
        // showPushAppInForeground
        showPushAppInForegroundTrueButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateShowPushAppInForeground(true)
        }), for:.touchUpInside)
        showPushAppInForegroundFalseButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateShowPushAppInForeground(false)
        }), for:.touchUpInside)

        // inAppRegion
        inAppRegionUSButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateInAppRegion(.US)
        }), for:.touchUpInside)
        inAppRegionEUButton.addAction(UIAction(handler: { [weak self] _ in
            self?.updateInAppRegion(.EU)
        }), for:.touchUpInside)
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

    // MARK: - Actions
    
    @IBAction func cdpApiKeyChanged(_ sender: UITextField) {
        settingsViewModel.cdpApiKeyUpdated(sender.text ?? "")
    }
    
    @IBAction func siteIdChanged(_ sender: UITextField) {
        settingsViewModel.sideIdUpdated(sender.text ?? "")
    }
    
    @IBAction func inAppSiteIdChanged(_ sender: UITextField) {
        settingsViewModel.inAppSideIdUpdated(sender.text ?? "")
    }
    
    @IBAction func internalSettingsButtonTapped(_ sender: Any) {
        settingsViewModel.internalSettingsScreenRequested()
    }

}
