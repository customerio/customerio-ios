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

        addNotifierObserver()
        configureLoginRouter()
        addUserInteractionToSettingsImageView()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func configureVersionLabel() {
        versionsLabel.text = getMetaData()
    }
    
    func addNotifierObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(routeToDeepLinkScreen(notification:)),
            name: Notification.Name("showDeepLinkScreenOnLogin"),
            object: nil
        )
    }

    @objc
    func routeToDeepLinkScreen(notification: Notification) {
        loginRouter?.routeToDeepLinkScreen()
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
            showToast(withMessage: "Email Id is mandatory to login into the app.")
            return
        }
        if let email = emailTextField.text, !email.isEmailValid {
            showToast(withMessage: "Invalid email id format.")
            return
        }
        guard let emailId = emailTextField.text, let name = firstNameTextField.text else {
            return
        }
        CustomerIO.shared.identify(identifier: emailId, body: ["first_name": name])
        storage.userEmailId = emailId
        storage.userName = name

        loginRouter?.routeToDashboard()
    }

    @IBAction func generateRandomCredentials(_ sender: UIButton) {
        let name = String.generateRandomString(ofLength: 10)
        let email = "\(name)@customer.io"
        // Generate Random Credentials does not create a first name.
        // Name is optional for login.
        emailTextField.text = email
    }

    func userDetailsValid() -> Bool {
        return !emailTextField.isTextTrimEmpty
    }
}
