import UIKit
import CioTracking

class LoginViewController: UIViewController {

    static func newInstance() -> LoginViewController {
        UIStoryboard.getViewController(identifier: "LoginViewController")
    }
    // MARK: - Outlets
    @IBOutlet weak var emailTextField: ThemeTextField!
    @IBOutlet weak var firstNameTextField: ThemeTextField!
    @IBOutlet weak var settings: UIImageView!
    
    var storage = DI.shared.storage
    var loginRouter: LoginRouting?
    
    override func viewWillAppear(_ animated: Bool) {
         super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = false
        emailTextField.clear()
        firstNameTextField.clear()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureLoginRouter()
        addUserInteractionToSettingsImageView()
    }
    
    func configureLoginRouter() {
        let router = LoginRouter()
        loginRouter = router
        router.loginViewController = self
    }
    
    func addUserInteractionToSettingsImageView() {
        settings.addTapGesture(onTarget: self, #selector(LoginViewController.settingsTapped))
    }
    
    @objc func settingsTapped() {
        loginRouter?.routeToSettings()
    }

    
    @IBAction func logInToApp(_ sender: UIButton) {
        
        if !userDetailsValid() {
            showAlert(withMessage: "Please fill all fields", .error)
            return
        }
        guard let emailId = emailTextField.text, let name = firstNameTextField.text else {
            return
        }
        CustomerIO.shared.identify(identifier: emailId, body: ["firstName" : name])
        storage.userEmailId = emailId
        storage.userName = name

        loginRouter?.routeToDashboard()
    }
    
    @IBAction func generateRandomCredentials(_ sender: UIButton) {
        let name = String.generateRandomString()
        let email  = "\(name)@customer.io"
        
        // Set values
        emailTextField.text = email
        firstNameTextField.text = name
        
        showAlert(withMessage: "Random user has been generated.")
    }
    
    func userDetailsValid() -> Bool {
        return !firstNameTextField.isTextTrimEmpty && !emailTextField.isTextTrimEmpty
    }
}
