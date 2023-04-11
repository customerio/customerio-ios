import UIKit

class LoginViewController: UIViewController {

    static func newInstance() -> LoginViewController {
        UIStoryboard.getViewController(identifier: "LoginViewController")
    }
    // MARK: - Outlets
    @IBOutlet weak var emailTextField: ThemeTextField!
    @IBOutlet weak var firstNameTextField: ThemeTextField!

    var loginRouter: LoginRouting?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureLoginRouter()
    }
    
    func configureLoginRouter() {
        let router = LoginRouter()
        loginRouter = router
        router.loginViewController = self
    }

    
    @IBAction func logInToApp(_ sender: UIButton) {
        
        if !userDetailsValid() {
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
    }
    
    func userDetailsValid() -> Bool {
        return !firstNameTextField.isTextTrimEmpty && !emailTextField.isTextTrimEmpty
    }
}
