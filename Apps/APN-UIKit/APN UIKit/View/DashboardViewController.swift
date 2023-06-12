import CioTracking
import UIKit

class DashboardViewController: UIViewController {
    static func newInstance() -> DashboardViewController {
        UIStoryboard.getViewController(identifier: "DashboardViewController")
    }

    @IBOutlet var userInfoLabel: UILabel!
    @IBOutlet var settings: UIImageView!

    var dashboardRouter: DashboardRouting?
    var notificationUtil = DIGraph.shared.notificationUtil
    var storage = DIGraph.shared.storage

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        showPushPermissionPrompt()
        configureDashboardRouter()
        addNotifierObserver()
        addUserInteractionToImageViews()
        setUserDetail()
    }

    func configureDashboardRouter() {
        let router = DashboardRouter()
        dashboardRouter = router
        router.dashboardViewController = self
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
            userInfoLabel.text = "[\(email)]"
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
        let randomEventName = String.generateRandomString(ofLength: 10)
        CustomerIO.shared.track(name: randomEventName)
        showAlert(withMessage: "Random event '\(randomEventName)' tracked successfully")
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
        
    }
    
}
