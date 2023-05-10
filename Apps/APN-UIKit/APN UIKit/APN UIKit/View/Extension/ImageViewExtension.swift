import Foundation
import UIKit

extension UIImageView {
    
    func addTapGesture(onTarget target : UIViewController, _ selector : Selector ) {
        let gestureOnSettings: UITapGestureRecognizer = UITapGestureRecognizer(target: target, action: selector)

        self.addGestureRecognizer(gestureOnSettings)
        self.isUserInteractionEnabled = true
    }
}
