import UIKit

extension UIView {
    func setAppiumAccessibilityId(_ value : String) {
        isAccessibilityElement = true
        accessibilityIdentifier = value
    }
}
