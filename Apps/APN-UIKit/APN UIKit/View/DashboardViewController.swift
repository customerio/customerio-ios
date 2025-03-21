import CioDataPipelines
import UIKit

class DashboardViewController: BaseViewController {
    static func newInstance() -> DashboardViewController {
        UIStoryboard.getViewController(identifier: "DashboardViewController")
    }

    @IBOutlet var userEmailLabel: UILabel!
    @IBOutlet var deviceTokenLabel: UILabel!
    @IBOutlet var sendDeviceAttributesButton: ThemeButton!
    @IBOutlet var showPushPromptButton: ThemeButton!
    @IBOutlet var logoutButton: ThemeButton!
    @IBOutlet var sendProfileAttributesButton: ThemeButton!
    @IBOutlet var customEventButton: ThemeButton!
    @IBOutlet var randomEventButton: ThemeButton!
    @IBOutlet var versionsLabel: UILabel!
    @IBOutlet var settings: UIImageView!
    var dashboardRouter: DashboardRouting?
    var notificationUtil = DIGraphShared.shared.notificationUtil
    var storage = DIGraphShared.shared.storage
    let randomData: [[String: Any?]] = [["name": "Order Purchased", "data": nil],
                                        ["name": "movie_watched", "data": ["movie_name": "The Incredibles"]],
                                        ["name": "appointmentScheduled", "data": ["appointmentTime": Date().addDaysToCurrentDate(days: 7)]]]
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureDashboardRouter()
        addNotifierObserver()
        addCopyOnTapToDeviceTokenLabel()
        addUserInteractionToImageViews()
        setEmailAndDeviceToken()
        configureVersionLabel()
        addAccessibilityIdentifiersForAppium()
    }

    func configureDashboardRouter() {
        let router = DashboardRouter()
        dashboardRouter = router
        router.dashboardViewController = self
    }

    func addCopyOnTapToDeviceTokenLabel() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(copyDeviceTokenToPasteboard))
        deviceTokenLabel.isUserInteractionEnabled = true
        deviceTokenLabel.addGestureRecognizer(tapGesture)
    }

    @objc func copyDeviceTokenToPasteboard() {
        UIPasteboard.general.string = deviceTokenLabel.text ?? ""
        showToast(withMessage: "Device id copied to pasteboard")
    }

    func configureVersionLabel() {
        let boldText = [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: UIFont.systemFontSize)]
        let regularText = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: UIFont.systemFontSize)]

        let versionLabelAttributedText = NSMutableAttributedString(string: "")
        for (key, value) in getMetadataAsSortedKeyValuePairs() {
            versionLabelAttributedText.append(NSAttributedString(string: "\(key): ", attributes: boldText))
            versionLabelAttributedText.append(NSAttributedString(string: "\(value)\n", attributes: regularText))
        }
        versionsLabel.attributedText = versionLabelAttributedText
    }

    func addUserInteractionToImageViews() {
        settings.addTapGesture(onTarget: self, #selector(DashboardViewController.settingsTapped))
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func addNotifierObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deepLinkRouteToSettings(notification:)),
            name: Notification.Name("showSettingsScreenOnDashboard"),
            object: nil
        )
    }

    @objc
    func deepLinkRouteToSettings(notification: Notification) {
        if let userInfo = notification.userInfo as? [String: String] {
            dashboardRouter?.routeToSettings(userInfo)
        }
    }

    @objc func settingsTapped() {
        dashboardRouter?.routeToSettings(nil)
    }

    func addAccessibilityIdentifiersForAppium() {
        setAppiumAccessibilityIdTo(settings, value: "Settings")
        setAppiumAccessibilityIdTo(randomEventButton, value: "Random Event Button")
        setAppiumAccessibilityIdTo(customEventButton, value: "Custom Event Button")
        setAppiumAccessibilityIdTo(sendDeviceAttributesButton, value: "Device Attribute Button")
        setAppiumAccessibilityIdTo(sendProfileAttributesButton, value: "Profile Attribute Button")
        setAppiumAccessibilityIdTo(showPushPromptButton, value: "Show Push Prompt Button")
        setAppiumAccessibilityIdTo(logoutButton, value: "Log Out Button")
    }

    func setEmailAndDeviceToken() {
        if let email = storage.userEmailId {
            userEmailLabel.text = email
        }
        deviceTokenLabel.text = CustomerIO.shared.registeredDeviceToken ?? "Not Registered"
    }

    // MARK: - Actions

    @IBAction func logoutUser(_ sender: UIButton) {
        storage.userEmailId = nil
        CustomerIO.shared.clearIdentify()
        dashboardRouter?.routeToLogin()
    }

    @IBAction func sendRandomEvent(_ sender: UIButton) {
        let randomInt = Int.random(in: 0 ..< 3)
        let randomEventInfo = randomData[randomInt]
        guard let name = randomEventInfo["name"] as? String else {
            return
        }
        showToast(withMessage: "Random event  tracked successfully")
        if let data = randomEventInfo["data"] as? [String: Any] {
            CustomerIO.shared.track(name: name, properties: data)
            return
        }
        CustomerIO.shared.track(name: name)
    }

    @IBAction func sendCustomEvent(_ sender: UIButton) {
        dashboardRouter?.routeToCustomDataScreen(forSource: .customEvents)
    }

    @IBAction func setDeviceAttributes(_ sender: UIButton) {
        dashboardRouter?.routeToCustomDataScreen(forSource: .deviceAttributes)
    }

    @IBAction func setProfileAttributes(_ sender: UIButton) {
        dashboardRouter?.routeToCustomDataScreen(forSource: .profileAttributes)
    }

    @IBAction func openInlineSwiftUiExamples(_ sender: UIButton) {
        dashboardRouter?.routeToInlineSwiftUiExamplesScreen()
    }

    @IBAction func openInlineUikitExamples(_ sender: UIButton) {
        dashboardRouter?.routeToInlineUikitExamplesScreen()
    }

    @IBAction func showPushPrompt(_ sender: UIButton) {
        notificationUtil.getPushPermission { status in
            if status == .notDetermined {
                self.notificationUtil.showPromptForPushPermission { _ in }
                return
            } else if status == .denied {
                if let appSettingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    DispatchQueue.main.async {
                        UIApplication.shared.open(appSettingsUrl)
                    }
                }
            } else {
                // Default as granted
                DispatchQueue.main.async {
                    self.showToast(withMessage: "Push permission status is - Granted")
                }
            }
        }
    }

    @IBAction func send3rdPartyPush(_ sender: UIButton) {
        // Display a local push notification on the system. This will test compatability when a push is clicked that was not sent by Customer.io.
        let content = UNMutableNotificationContent()
        content.title = "local push"
        content.body = "Try clicking me and see host app handle the push instead of Customer.io SDK"
        let request = UNNotificationRequest(identifier: "local-push-not-from-cio", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
