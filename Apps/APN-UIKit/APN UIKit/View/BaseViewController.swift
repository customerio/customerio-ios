import UIKit

// Use this Base controller class to implement shared functionality
// across all controllers in the project
class BaseViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        dismissKeyboardOnTap()
        overrideUserInterfaceStyle = .light
    }

    func getMetaData() -> String {
        let metadata = BuildInfoMetadata()
        return metadata.description
    }

    func setAppiumAccessibilityIdTo(_ element: UIView, value: String) {
        element.isAccessibilityElement = true
        element.accessibilityIdentifier = value
    }
}
