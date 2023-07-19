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
        let versionDetail = "SDK: Customer.io iOS SDK \(MetadataUtil.cioSdkVersion)\nApp: \(MetadataUtil.appName) \(MetadataUtil.appBuildVersion) \(MetadataUtil.appBuildNumber)"
        return versionDetail
    }

    func setAppiumAccessibilityIdTo(_ element: UIView, value: String) {
        element.isAccessibilityElement = true
        element.accessibilityIdentifier = value
    }
}
