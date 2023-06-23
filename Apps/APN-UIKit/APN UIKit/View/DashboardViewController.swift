import CioTracking
import UIKit

class DashboardViewController: BaseViewController {
    static func newInstance() -> DashboardViewController {
        UIStoryboard.getViewController(identifier: "DashboardViewController")
    }

    @IBOutlet var versionsLabel: UILabel!
    @IBOutlet var userInfoLabel: UILabel!
    @IBOutlet var settings: UIImageView!

    var dashboardRouter: DashboardRouting?
    var notificationUtil = DIGraph.shared.notificationUtil
    var storage = DIGraph.shared.storage

    let randomData : [[String: Any?]] = [["name" : "Order Purchased", "data": nil],
                                         ["name" : "Movie_watched", "data" : ["movie_name" : "The Incredibles"]],
                                         ["name" : "appointmentScheduled", "data": ["appointmentTime": NSDate().timeIntervalSince1970]]]
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureDashboardRouter()
        addNotifierObserver()
        addUserInteractionToImageViews()
        setUserDetail()
        configureVersionLabel()
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
            selector: #selector(routeToDeepLinkScreen(notification:)),
            name: Notification.Name("showDeepLinkScreenOnDashboard"),
            object: nil
        )
    }

    @objc
    func routeToDeepLinkScreen(notification: Notification) {
        if let userInfo = notification.userInfo as? [String: String] {
            dashboardRouter?.routeToDeepLinkScreen(withInfo: userInfo)
        }
    }

    @objc func settingsTapped() {
        dashboardRouter?.routeToSettings()
    }

    func setUserDetail() {
        if let email = storage.userEmailId {
            userInfoLabel.text = email
        }
    }

    // MARK: - Actions

    @IBAction func logoutUser(_ sender: UIButton) {
        storage.userEmailId = nil
        storage.userName = nil
        CustomerIO.shared.clearIdentify()
        dashboardRouter?.routeToLogin()
    }

    @IBAction func sendRandomEvent(_ sender: UIButton) {
        
        let randomInt = Int.random(in: 0..<3)
        let randomEventInfo = randomData[randomInt]
        guard let name = randomEventInfo["name"] as? String else {
            return
        }
        showToast(withMessage: "Random event  tracked successfully")
        if let data = randomEventInfo["data"] as? [String: Any] {
            CustomerIO.shared.track(name: name, data: data)
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
                self.notificationUtil.showPromptForPushPermission { _ in}
                return
            }
            let pushStatus = status == .denied ? "Denied" : "Granted"
            DispatchQueue.main.async {
                self.showToast(withMessage: "Push permission status is - \(pushStatus)")

            }
        }
    }
}
