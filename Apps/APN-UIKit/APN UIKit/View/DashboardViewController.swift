import CioDataPipelines
import CioInternalCommon
import CioMessagingInbox
import SwiftUI
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
    @IBOutlet var inboxButton: ThemeButton!
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
        addVisualInboxOverlay()
    }

    /// Demonstrates the drop-in Visual Notification Inbox integration: mount the SDK's public
    /// `NotificationInboxOverlay` (floating bell + slide-out panel + dismiss scrim) on top of the
    /// screen. Because the overlay is SwiftUI and this is a UIKit host, it's hosted in a full-screen
    /// passthrough view: while the panel is closed, taps outside the bell fall through to the
    /// dashboard; while it's open, the overlay captures them (so the scrim blocks click-through).
    /// `onPanelPresentationChange` drives that capture toggle. The bell hides itself when there is
    /// nothing to show.
    private func addVisualInboxOverlay() {
        guard #available(iOS 15.0, *) else { return }
        let passthrough = InboxOverlayPassthroughView()
        passthrough.backgroundColor = .clear
        let overlay = NotificationInboxOverlay(onPanelPresentationChange: { [weak passthrough] isOpen in
            // Capture full-screen touches only while the panel is presented; pass through otherwise.
            passthrough?.capturesAllTouches = isOpen
        })
        let host = UIHostingController(rootView: overlay)
        host.view.backgroundColor = .clear
        addChild(host)
        passthrough.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passthrough)
        passthrough.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            passthrough.topAnchor.constraint(equalTo: view.topAnchor),
            passthrough.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            passthrough.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            passthrough.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.topAnchor.constraint(equalTo: passthrough.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: passthrough.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: passthrough.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: passthrough.bottomAnchor)
        ])
        host.didMove(toParent: self)
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
        setAccessibilityId(settings, to: "Settings")
        setAccessibilityId(randomEventButton, to: "Random Event Button")
        setAccessibilityId(customEventButton, to: "custom_event_button")
        setAccessibilityId(sendDeviceAttributesButton, to: "Device Attribute Button")
        setAccessibilityId(sendProfileAttributesButton, to: "Profile Attribute Button")
        setAccessibilityId(showPushPromptButton, to: "Show Push Prompt Button")
        setAccessibilityId(inboxButton, to: "View Inbox Button")
        setAccessibilityId(logoutButton, to: "Log Out Button")
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

    @IBAction func openInbox(_ sender: UIButton) {
        dashboardRouter?.routeToInbox()
    }

    @IBAction func send3rdPartyPush(_ sender: UIButton) {
        // Display a local push notification on the system. This will test compatability when a push is clicked that was not sent by Customer.io.
        let content = UNMutableNotificationContent()
        content.title = "local push"
        content.body = "Try clicking me and see host app handle the push instead of Customer.io SDK"
        let request = UNNotificationRequest(identifier: "local-push-not-from-cio", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    @IBAction func openLocationTest(_ sender: UIButton) {
        dashboardRouter?.routeToLocationTest()
    }
}

/// Full-screen container that hosts the SwiftUI `NotificationInboxOverlay` in a UIKit screen.
///
/// While the inbox panel is closed (`capturesAllTouches == false`) only the floating bell's
/// bottom-trailing corner stays interactive; touches anywhere else fall through to the views behind
/// it, so the dashboard stays usable. While the panel is open the overlay's scrim must block
/// click-through, so the host flips `capturesAllTouches` to `true` via `onPanelPresentationChange`
/// and the container captures the full screen.
///
/// We gate the closed state on an explicit corner zone rather than SwiftUI's "no hit on empty space"
/// behavior: once the hosting view has laid out the full-screen scrim/panel, it no longer reports
/// empty regions as passthrough, which would otherwise leave the whole screen capturing touches
/// after the panel is opened once.
private final class InboxOverlayPassthroughView: UIView {
    /// Set from `NotificationInboxOverlay`'s `onPanelPresentationChange`: `true` while the panel is open.
    var capturesAllTouches = false

    /// Size of the bottom-trailing square kept interactive while the panel is closed — large enough to
    /// cover the overlay's floating bell (56pt) + its 16pt padding + unread badge overhang.
    private let bellZoneSize: CGFloat = 160

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if capturesAllTouches {
            return super.hitTest(point, with: event)
        }
        // Panel closed: only the bell's corner is interactive; pass everything else through.
        let bellZone = CGRect(
            x: bounds.maxX - bellZoneSize,
            y: bounds.maxY - bellZoneSize,
            width: bellZoneSize,
            height: bellZoneSize
        )
        guard bellZone.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}
