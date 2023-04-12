import UIKit

enum CustomDataSource {
    case customEvents
    case deviceAttributes
    case profileAttributes
}

class CustomDataViewController: UIViewController {

    @IBOutlet weak var eventNameTextField: ThemeTextField!
    @IBOutlet weak var propertyValueTextField: ThemeTextField!
    @IBOutlet weak var propertyNameTextField: ThemeTextField!
    @IBOutlet weak var headerLabel: UILabel!
    
    @IBOutlet weak var eventNameLabel: UILabel!
    @IBOutlet weak var propertyValueLabel: UILabel!
    @IBOutlet weak var propertyNameLabel: UILabel!
    var source : CustomDataSource = .customEvents
    static func newInstance() -> CustomDataViewController {
        UIStoryboard.getViewController(identifier: "CustomDataViewController")
    }
    
    override func viewWillAppear(_ animated: Bool) {
         super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = false
        customizeScreenBasedOnSource()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    func customizeScreenBasedOnSource() {
        
        if source == .customEvents {
            headerLabel.text = "Send Custom Event"
        }
        else {
            headerLabel.text = source == .deviceAttributes ? "Set Custom Device Attribute" : "Set Custom Profile Atrribute"
            eventNameLabel.isHidden = true
            eventNameTextField.isHidden = true
            propertyNameLabel.text = "Attribute Name"
            propertyValueLabel.text = "Attribute Value"
        }
    }

    // MARK: - Actions
    
    @IBAction func sendCustomData(_ sender: UIButton) {
        
        if ( source == .customEvents) {
            self.showInfoAlert(withMessage: "Name = \(eventNameTextField.text ?? "") and property name  = \(propertyNameTextField.text ?? "") and property value = \(propertyValueTextField.text ?? "")")
        }
    }
    
}
