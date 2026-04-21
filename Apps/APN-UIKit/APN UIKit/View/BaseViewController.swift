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

    func getMetadataAsSortedKeyValuePairs() -> [(String, String)] {
        let metadata = BuildInfoMetadata()
        return metadata.asSortedKeyValuePairs
    }

    /// Tag a view with an accessibility identifier so E2E runners (Maestro,
    /// XCUITest, Appium) and screen readers (VoiceOver) can find it by
    /// stable id. Mirrors the Android `ViewUtils.setAccessibilityId`.
    func setAccessibilityId(_ element: UIView, to value: String) {
        element.isAccessibilityElement = true
        element.accessibilityIdentifier = value
    }
}
