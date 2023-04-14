import UIKit
import CioTracking

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
        if propertyValueTextField.isTextTrimEmpty ||
            propertyValueTextField.isTextTrimEmpty ||
            (source == .customEvents && eventNameTextField.isTextTrimEmpty) {
            showAlert(withMessage: "Please fill all fields", .error)
            return
        }
    }

    // MARK: - Actions
    
    @IBAction func sendCustomData(_ sender: UIButton) {
        isAllTextFieldsValid()
        
        guard let propName = propertyNameTextField.text, let propValue = propertyValueTextField.text else {
            return
        }
        if ( source == .customEvents) {
            guard let eventName = eventNameTextField.text else { return }
            CustomerIO.shared.track(name: eventName, data: [propName: propValue])
            self.showAlert(withMessage: "Custom event tracked successfully")
        }
        else if ( source == .profileAttributes) {
            CustomerIO.shared.deviceAttributes = [propName : propValue]
            self.showAlert(withMessage: "Device attribute set successfully.")
        }
        else if ( source == .deviceAttributes) {
            CustomerIO.shared.profileAttributes = [propName: propValue]
            self.showAlert(withMessage: "Profile attribute set successfully.")
        }
    }
    
}
