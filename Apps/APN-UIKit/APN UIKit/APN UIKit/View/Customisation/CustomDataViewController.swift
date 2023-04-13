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
            headerLabel.text = source == .deviceAttributes ? "Set Custom Device Attribute" : "Set Custom Profile Attribute"
            eventNameLabel.isHidden = true
            eventNameTextField.isHidden = true
            propertyNameLabel.text = "Attribute Name"
            propertyValueLabel.text = "Attribute Value"
        }
    }
    
    func isAllTextFieldsValid() {
        var allFieldsValid = true
        if propertyValueTextField.isTextTrimEmpty || propertyValueTextField.isTextTrimEmpty || (source == .customEvents && eventNameTextField.isTextTrimEmpty) {
            allFieldsValid = false
        }
        if !allFieldsValid {
            showAlert(withMessage: "Please fill all fields", .error)
        }
    }

    // MARK: - Actions
    
    @IBAction func sendCustomData(_ sender: UIButton) {
        isAllTextFieldsValid()
        
        if ( source == .customEvents) {
            self.showAlert(withMessage: "Name = \(eventNameTextField.text ?? "") and property name  = \(propertyNameTextField.text ?? "") and property value = \(propertyValueTextField.text ?? "")")
        }
        else if ( source == .profileAttributes) {
            self.showAlert(withMessage: "Attribute name  = \(propertyNameTextField.text ?? "") and property value = \(propertyValueTextField.text ?? "")")
        }
        else if ( source == .deviceAttributes) {
            self.showAlert(withMessage: "Attribute name  = \(propertyNameTextField.text ?? "") and property value = \(propertyValueTextField.text ?? "")")
        }
    }
    
}
