import CioDataPipelines
import CioMessagingInApp
import UIKit

class DashboardViewController: BaseViewController {
    static func newInstance() -> DashboardViewController {
        UIStoryboard.getViewController(identifier: "DashboardViewController")
    }

    @IBOutlet var sendDeviceAttributesButton: ThemeButton!
    @IBOutlet var showPushPromptButton: ThemeButton!
    @IBOutlet var logoutButton: ThemeButton!
    @IBOutlet var sendProfileAttributesButton: ThemeButton!
    @IBOutlet var customEventButton: ThemeButton!
    @IBOutlet var randomEventButton: ThemeButton!
    @IBOutlet var versionsLabel: UILabel!
    @IBOutlet var userInfoLabel: UILabel!
    @IBOutlet var settings: UIImageView!
    @IBOutlet var inlineInAppViewCreatedInStoryboard: InAppMessageView!
    @IBOutlet var buttonStackView: UIStackView!

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

        // For inline Views added with Storyboard, set the elementId to finish setup of the View and begin showing messages.
        inlineInAppViewCreatedInStoryboard.elementId = "dashboard-announcement"

        // This is optional. If set, the delegate method `onActionClick`
        // will receive callbacks.
        // If not set, the global method `messageActionTaken` will handle the callbacks.
        inlineInAppViewCreatedInStoryboard.onActionDelegate = self

        // We want to test that Inline Views can be used by customers who prefer to use code to make the UI.
        // Construct a new instance of the View, add it to the ViewController, then set constraints to make it visible.
        let newInlineViewUsingUIAsCode = InAppMessageView(elementId: "dashboard-announcement-code")
        // Add the View to the screen.
        // It's important that we test inline Views that are nested in a UIStackView. See comments in inline View code to learn more.
        buttonStackView.addArrangedSubview(newInlineViewUsingUIAsCode)

        // Customers are responsible for setting the width of the View.
        newInlineViewUsingUIAsCode.translatesAutoresizingMaskIntoConstraints = false
        newInlineViewUsingUIAsCode.widthAnchor.constraint(equalTo: buttonStackView.widthAnchor).isActive = true

        configureDashboardRouter()
        addNotifierObserver()
        addUserInteractionToImageViews()
        setUserDetail()
        configureVersionLabel()
        addAccessibilityIdentifiersForAppium()
    }

    func configureDashboardRouter() {
        let router = DashboardRouter()
        dashboardRouter = router
        router.dashboardViewController = self
    }

    func configureVersionLabel() {
        versionsLabel.text = getMetaData()
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

    func setUserDetail() {
        if let email = storage.userEmailId {
            userInfoLabel.text = email
        }
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

extension DashboardViewController: InAppMessageViewActionDelegate {
    func onActionClick(message: InAppMessage, actionValue: String, actionName: String) {
        print("You can perform any action here. For instance, we are tracking the custom button tap.")
        CustomerIO.shared.track(name: "inline custom button action", properties: [
            "delivery-id": message.deliveryId ?? "(none)",
            "message-id": message.messageId,
            "action-value": actionValue,
            "action-name": actionName
        ])
    }
}
