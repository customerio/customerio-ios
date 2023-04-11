import UIKit

class DashboardViewController: UIViewController {

    static func newInstance() -> DashboardViewController {
        UIStoryboard.getViewController(identifier: "DashboardViewController")
    }
    
    var dashboardRouter: DashboardRouting?
    override func viewDidLoad() {
        super.viewDidLoad()

        configureDashboardRouter()
    }
    
    func configureDashboardRouter() {
        let router = DashboardRouter()
        dashboardRouter = router
        router.dashboardViewController = self
    }
    
    // MARK: - Actions
    
    @IBAction func logoutUser(_ sender: UIButton) {
        dashboardRouter?.routeToLogin()
    }
    
    @IBAction func sendRandomEvent(_ sender: UIButton) {
        self.showInfoAlert(withMessage: "Random event tracked successfully")
    }
    
    @IBAction func sendCustomEvent(_ sender: UIButton) {
    }
    
    @IBAction func setDeviceAttributes(_ sender: UIButton) {
    }
    
    @IBAction func setProfileAttributes(_ sender: UIButton) {
    }
}
