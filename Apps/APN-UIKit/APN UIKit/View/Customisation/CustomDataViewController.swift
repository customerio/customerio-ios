import CioTracking
import UIKit

enum CustomDataSource {
    case customEvents
    case deviceAttributes
    case profileAttributes
}

class CustomDataViewController: BaseViewController {
    @IBOutlet var eventNameTextField: ThemeTextField!
    @IBOutlet var propertyValueTextField: ThemeTextField!
    @IBOutlet var propertyNameTextField: ThemeTextField!
    @IBOutlet var headerLabel: UILabel!
    @IBOutlet var sendButton: ThemeButton!
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
            sendButton.setTitle(source == .deviceAttributes ? "Send device attributes" : "Send profile attributes", for: .normal)
            eventNameLabel.isHidden = true
            eventNameTextField.isHidden = true
            propertyNameLabel.text = "Attribute Name*"
            propertyValueLabel.text = "Attribute Value*"
        }
    }

    func isAllTextFieldsValid() -> Bool {
        if source == .customEvents {
            return !eventNameTextField.isTextTrimEmpty
        } else {
            return !(propertyValueTextField.isTextTrimEmpty || propertyNameTextField.isTextTrimEmpty)
        }
    }

    // MARK: - Actions

    @IBAction func sendCustomData(_ sender: UIButton) {
        if !isAllTextFieldsValid() {
            showToast(withMessage: "Please fill all * marked fields.")
            return
        }

        guard let propName = propertyNameTextField.text, let propValue = propertyValueTextField.text else {
            return
        }
        if source == .customEvents {
            guard let eventName = eventNameTextField.text else { return }
            CustomerIO.shared.track(name: eventName, data: [propName: propValue])
            showToast(withMessage: "Custom event tracked successfully")
        } else if source == .deviceAttributes {
            CustomerIO.shared.deviceAttributes = [propName: propValue]
            showToast(withMessage: "Device attribute set successfully.")
        } else if source == .profileAttributes {
            CustomerIO.shared.profileAttributes = [propName: propValue]
            showToast(withMessage: "Profile attribute set successfully.")
        }
    }
}
