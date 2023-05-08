import UIKit

enum CustomDataSource {
    case customEvents
    case deviceAttributes
    case profileAttributes
}

class CustomDataViewController: UIViewController {
    @IBOutlet var eventNameTextField: ThemeTextField!
    @IBOutlet var propertyValueTextField: ThemeTextField!
    @IBOutlet var propertyNameTextField: ThemeTextField!
    @IBOutlet var headerLabel: UILabel!

    @IBOutlet var eventNameLabel: UILabel!
    @IBOutlet var propertyValueLabel: UILabel!
    @IBOutlet var propertyNameLabel: UILabel!
    var source: CustomDataSource = .customEvents
    static func newInstance() -> CustomDataViewController {
        UIStoryboard.getViewController(identifier: "CustomDataViewController")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = false
        customizeScreenBasedOnSource()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }

    func customizeScreenBasedOnSource() {
        if source == .customEvents {
            headerLabel.text = "Send Custom Event"
        } else {
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

        if source == .customEvents {
            showAlert(withMessage: "Name = \(eventNameTextField.text ?? "") and property name  = \(propertyNameTextField.text ?? "") and property value = \(propertyValueTextField.text ?? "")")
        } else if source == .profileAttributes {
            showAlert(withMessage: "Attribute name  = \(propertyNameTextField.text ?? "") and property value = \(propertyValueTextField.text ?? "")")
        } else if source == .deviceAttributes {
            showAlert(withMessage: "Attribute name  = \(propertyNameTextField.text ?? "") and property value = \(propertyValueTextField.text ?? "")")
        }
    }
}
