import UIKit
import CioTracking

class DashboardViewController: UIViewController {

    static func newInstance() -> DashboardViewController {
        UIStoryboard.getViewController(identifier: "DashboardViewController")
    }
    
    @IBOutlet weak var settings: UIImageView!
    
    var dashboardRouter: DashboardRouting?
    
    override func viewWillAppear(_ animated: Bool) {
         super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        showPushPermissionPrompt()
        configureDashboardRouter()
        addUserInteractionToSettingsImageView()
    }
    
    func showPushPermissionPrompt() {
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions, completionHandler: { _, _ in })
    }
    func configureDashboardRouter() {
        let router = DashboardRouter()
        dashboardRouter = router
        router.dashboardViewController = self
    }
    
    func addUserInteractionToSettingsImageView() {
        let gestureOnSettings: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(LoginViewController.settingsTapped))

        settings.addGestureRecognizer(gestureOnSettings)
        settings.isUserInteractionEnabled = true
    }
    
    @objc func settingsTapped() {
        dashboardRouter?.routeToSettings()
    }
    
    // MARK: - Actions
    
    @IBAction func logoutUser(_ sender: UIButton) {
        CustomerIO.shared.clearIdentify()
        dashboardRouter?.routeToLogin()
    }
    
    @IBAction func sendRandomEvent(_ sender: UIButton) {
        let randomEventName = String.generateRandomString(ofLength: 10)
        CustomerIO.shared.track(name: randomEventName)
        self.showAlert(withMessage: "Random event '\(randomEventName)' tracked successfully")
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
}
