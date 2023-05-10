import UIKit
import CioTracking

class DashboardViewController: UIViewController {

    static func newInstance() -> DashboardViewController {
        UIStoryboard.getViewController(identifier: "DashboardViewController")
    }
    
    @IBOutlet weak var userDetail: UIImageView!
    @IBOutlet weak var settings: UIImageView!
    
    var dashboardRouter: DashboardRouting?
    var notificationUtil = DI.shared.notificationUtil
    var storage =  DI.shared.storage
    
    override func viewWillAppear(_ animated: Bool) {
         super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        showPushPermissionPrompt()
        configureDashboardRouter()
        addUserInteractionToImageViews()
    }
    
    func showPushPermissionPrompt() {
        notificationUtil.showPromptForPushPermission()
    }
    
    func configureDashboardRouter() {
        let router = DashboardRouter()
        dashboardRouter = router
        router.dashboardViewController = self
    }
    
    func addUserInteractionToImageViews() {
        settings.addTapGesture(onTarget: self, #selector(DashboardViewController.settingsTapped))
        userDetail.addTapGesture(onTarget: self, #selector(DashboardViewController.userDetailTapped))
    }
    
    @objc func settingsTapped() {
        dashboardRouter?.routeToSettings()
    }
    
    @objc func userDetailTapped() {
        let userDetail = "Name - " + storage.userName! + "\n\nEmailId - " + storage.userEmailId!
        showAlert(withMessage: userDetail)
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
