import CioDataPipelines
import CioInternalCommon
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
        addAccessibilityIdentifiersForAppium()
    }

    func addAccessibilityIdentifiersForAppium() {
        if source == .customEvents {
            setAccessibilityId(eventNameTextField, to: "event_name_input")
            setAccessibilityId(propertyNameTextField, to: "property_name_input")
            setAccessibilityId(propertyValueTextField, to: "property_value_input")
            setAccessibilityId(sendButton, to: "send_event_button")
        } else {
            setAccessibilityId(sendButton, to: "Set \(source == .deviceAttributes ? "Device" : "Profile") Attribute Button")
            setAccessibilityId(propertyNameTextField, to: "Attribute Name Input")
            setAccessibilityId(propertyValueTextField, to: "Attribute Value Input")
        }
        let backButton = UIBarButtonItem()
        backButton.accessibilityIdentifier = "Back Button"
        backButton.isAccessibilityElement = true
        navigationController?.navigationBar.topItem?.backBarButtonItem = backButton
    }

    func customizeScreenBasedOnSource() {
        if source == .customEvents {
            headerLabel.text = "Send Custom Event"
        } else {
            headerLabel.text = source == .deviceAttributes ? "Set Custom Device Attribute" : "Set Custom Profile Attribute"
            sendButton.setTitle(source == .deviceAttributes ? "Send device attributes" : "Send profile attributes", for: .normal)
            eventNameLabel.isHidden = true
            eventNameTextField.isHidden = true
            propertyNameLabel.text = "Attribute Name"
            propertyValueLabel.text = "Attribute Value"
        }
    }

    func canEventFail() -> Bool {
        if source == .customEvents {
            return eventNameTextField.isTextTrimEmpty
        } else {
            return propertyValueTextField.isTextTrimEmpty || propertyNameTextField.isTextTrimEmpty
        }
    }

    // MARK: - Actions

    @IBAction func sendCustomData(_ sender: UIButton) {
        guard let propName = propertyNameTextField.text, let propValue = propertyValueTextField.text else {
            return
        }
        var toastMessage = ""
        if source == .customEvents {
            guard let eventName = eventNameTextField.text else { return }
            CustomerIO.shared.track(name: eventName, properties: [propName: propValue])
            toastMessage = "Custom event tracked successfully"
        } else if source == .deviceAttributes {
            CustomerIO.shared.deviceAttributes = [propName: propValue]
            toastMessage = "Device attribute set successfully."
        } else if source == .profileAttributes {
            CustomerIO.shared.setProfileAttributes([propName: propValue])
            toastMessage = "Profile attribute set successfully."
        }
        if canEventFail() {
            // Toast message might need to be changed based on squad discussion
            toastMessage = "Event sent.\nNote:- Custom event sent without any data might result in API failure."
        }
        showToast(withMessage: toastMessage)
    }
}
