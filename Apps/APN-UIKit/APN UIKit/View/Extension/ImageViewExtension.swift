import Foundation
import UIKit

extension UIImageView {
    func addTapGesture(onTarget target: UIViewController, _ selector: Selector) {
        let gestureOnSettings = UITapGestureRecognizer(target: target, action: selector)

        addGestureRecognizer(gestureOnSettings)
        isUserInteractionEnabled = true
    }
}
