import UIKit

class CustomDataViewController: UIViewController {

    @IBOutlet weak var eventNameTextField: ThemeTextField!
    @IBOutlet weak var propertyValueTextField: ThemeTextField!
    @IBOutlet weak var propertyNameTextField: ThemeTextField!
    
    static func newInstance() -> CustomDataViewController {
        UIStoryboard.getViewController(identifier: "CustomDataViewController")
    }
    
    override func viewWillAppear(_ animated: Bool) {
         super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = false
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    // MARK: - Actions
    

}
