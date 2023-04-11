import UIKit

class LoginViewController: UIViewController {

    // MARK: - Outlets
    
    @IBOutlet weak var emailTextField: ThemeTextField!
    @IBOutlet weak var firstNameTextField: ThemeTextField!
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    @IBAction func logInToApp(_ sender: UIButton) {
        
        if !userDetailsValid() {
            return
        }
        
        
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
