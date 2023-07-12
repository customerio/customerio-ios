import CioTracking
import UIKit

class LoginViewController: BaseViewController {
    static func newInstance() -> LoginViewController {
        UIStoryboard.getViewController(identifier: "LoginViewController")
    }

    // MARK: - Outlets

    @IBOutlet var emailTextField: ThemeTextField!
    @IBOutlet var firstNameTextField: ThemeTextField!
    @IBOutlet var settings: UIImageView!
    @IBOutlet var versionsLabel: UILabel!
    @IBOutlet var loginButton: ThemeButton!
    @IBOutlet var randomLoginButton: UIButton!
    var storage = DIGraph.shared.storage
    var loginRouter: LoginRouting?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = true
        emailTextField.clear()
        firstNameTextField.clear()
        configureVersionLabel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        addAccessibilityIdentifiersForAppium()
        addNotifierObserver()
        configureLoginRouter()
        addUserInteractionToSettingsImageView()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func addAccessibilityIdentifiersForAppium() {
        setAppiumAccessibilityIdTo(settings, value: "Settings")
        setAppiumAccessibilityIdTo(firstNameTextField, value: "First Name Input")
        setAppiumAccessibilityIdTo(emailTextField, value: "Email Input")
        setAppiumAccessibilityIdTo(loginButton, value: "Login Button")
        setAppiumAccessibilityIdTo(randomLoginButton, value: "Random Login Button")
    }

    func configureVersionLabel() {
        versionsLabel.text = getMetaData()
    }

    func addNotifierObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deepLinkRouteToSettings(notification:)),
            name: Notification.Name("showSettingsScreenOnLogin"),
            object: nil
        )
    }

    @objc
    func deepLinkRouteToSettings(notification: Notification) {
        if let userInfo = notification.userInfo as? [String: String] {
            loginRouter?.routeToSettings(userInfo)
        }
    }

    func configureLoginRouter() {
        let router = LoginRouter()
        loginRouter = router
        router.loginViewController = self
    }

    func addUserInteractionToSettingsImageView() {
        settings.addTapGesture(onTarget: self, #selector(LoginViewController.settingsTapped))
    }

    func validateAndLogin() {
        if !userDetailsValid() {
            showToast(withMessage: "Email Id is mandatory to login into the app.")
            return
        }
        if let email = emailTextField.text, !email.isEmailValid {
            showToast(withMessage: "Invalid email id format.")
            return
        }
        var body: [String: String]?
        guard let emailId = emailTextField.text else {
            return
        }
        if let name = firstNameTextField.text, !name.isEmpty {
            body = ["first_name": name]
        }
        CustomerIO.shared.identify(identifier: emailId, body: body)
        storage.userEmailId = emailId
        loginRouter?.routeToDashboard()
    }

    @objc func settingsTapped() {
        loginRouter?.routeToSettings(nil)
    }

    @IBAction func logInToApp(_ sender: UIButton) {
        validateAndLogin()
    }

    @IBAction func generateRandomCredentials(_ sender: UIButton) {
        let name = String.generateRandomString(ofLength: 10)
        let email = "\(name)@customer.io"
        // Generate Random Credentials does not create a first name.
        // Name is optional for login.
        emailTextField.text = email
        validateAndLogin()
    }

    func userDetailsValid() -> Bool {
        !emailTextField.isTextTrimEmpty
    }
}
