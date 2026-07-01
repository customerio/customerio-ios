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
            // Capture full-screen touches while the panel is presented; pass through otherwise. The
            // view keeps capturing briefly after `isOpen` flips false so taps don't leak to the
            // dashboard through the still-fading scrim.
            passthrough?.setPanelPresented(isOpen)
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
/// While the panel is presented the container captures the full screen so the overlay's scrim blocks
/// click-through. While it's closed, only the floating bell's bottom-trailing corner stays
/// interactive — and only if the overlay actually drew the bell there — so touches elsewhere (and an
/// empty corner when the inbox is hidden) fall through to the dashboard.
///
/// NOTE: this is a **sample-grade** hand-rolled hit-test for embedding a SwiftUI overlay in a UIKit
/// host, with inherent edge cases — e.g. touch capture is held for `closeSettleDelay` so taps don't
/// leak through the fading scrim, which can briefly (~0.45s) block the dashboard if the inbox hides
/// *instantly* (rather than via a panel close). In a SwiftUI app, mount `NotificationInboxOverlay`
/// directly in a `ZStack` (see the CocoaPods-FCM sample) — SwiftUI handles touch passthrough
/// natively and none of this container is needed.
private final class InboxOverlayPassthroughView: UIView {
    /// `true` while the panel is presented or still animating closed; the container then captures the
    /// full screen. Driven indirectly via `setPanelPresented(_:)`.
    private var capturesAllTouches = false

    /// Pending "stop capturing" work, scheduled when the panel closes and cancelled if it reopens.
    private var endCaptureWorkItem: DispatchWorkItem?

    /// Roughly the panel's close-animation settle time. Capture is held this long after the panel
    /// reports closed so taps don't leak to the dashboard through the still-fading scrim.
    private let closeSettleDelay: TimeInterval = 0.45

    /// Size of the bottom-trailing square kept interactive while the panel is closed — large enough to
    /// cover the overlay's floating bell (56pt) + its 16pt padding + unread badge overhang.
    private let bellZoneSize: CGFloat = 160

    /// Driven by `NotificationInboxOverlay.onPanelPresentationChange`: capture turns on immediately on
    /// open, and turns off only after `closeSettleDelay` on close (a reopen within the window cancels
    /// the pending turn-off), so the fading scrim keeps blocking taps during the close animation.
    func setPanelPresented(_ presented: Bool) {
        endCaptureWorkItem?.cancel()
        endCaptureWorkItem = nil
        if presented {
            capturesAllTouches = true
        } else {
            let work = DispatchWorkItem { [weak self] in self?.capturesAllTouches = false }
            endCaptureWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + closeSettleDelay, execute: work)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if capturesAllTouches {
            return super.hitTest(point, with: event)
        }
        // Panel closed: only the bell's corner is interactive. The overlay pins the bell to SwiftUI's
        // bottom-TRAILING corner — right in LTR, left in RTL — so anchor the zone to the trailing edge
        // per the resolved layout direction.
        let originX = effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? bounds.minX
            : bounds.maxX - bellZoneSize
        let bellZone = CGRect(x: originX, y: bounds.maxY - bellZoneSize, width: bellZoneSize, height: bellZoneSize)
        guard bellZone.contains(point) else { return nil }
        // Within the corner, capture only if the overlay actually drew content there (the bell). When
        // the inbox is hidden no bell is drawn, so `super.hitTest` resolves to this container — pass
        // through (return nil) to keep the dashboard usable under an empty corner.
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
