import UIKit

class LoginViewController: UIViewController {

    static func newInstance() -> LoginViewController {
        UIStoryboard.getViewController(identifier: "LoginViewController")
    }
    // MARK: - Outlets
    @IBOutlet weak var emailTextField: ThemeTextField!
    @IBOutlet weak var firstNameTextField: ThemeTextField!
    @IBOutlet weak var settings: UIImageView!
    
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
        let gestureOnSettings: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(LoginViewController.settingsTapped))

        settings.addGestureRecognizer(gestureOnSettings)
        settings.isUserInteractionEnabled = true
    }
    
    @objc func settingsTapped() {
        loginRouter?.routeToSettings()
    }

    
    @IBAction func logInToApp(_ sender: UIButton) {
        
        if !userDetailsValid() {
            showAlert(withMessage: "Please fill all fields", .error)
            return
        }
        loginRouter?.routeToDashboard()
    }
    
    @IBAction func generateRandomCredentials(_ sender: UIButton) {
        let letters = "AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890"
        let name = (String((0..<15).map{ _ in letters.randomElement()! }))
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
