import Foundation
import UIKit

extension UIView {
    // Find the topmost superview in the view hierarchy. Probably the UIView of the UIViewController the UIView is nested in.
    func getRootSuperview() -> UIView? {
        guard var rootSuperview = superview else {
            return nil // no superview, return nil early.
        }

        while true {
            if let nextLevelSuperview = rootSuperview.superview {
                rootSuperview = nextLevelSuperview
            } else {
                return rootSuperview
            }
        }
    }

    var heightConstraints: [NSLayoutConstraint] {
        constraints.filter { $0.firstAnchor == heightAnchor }
    }

    var widthConstraints: [NSLayoutConstraint] {
        constraints.filter { $0.firstAnchor == widthAnchor }
    }

    var heightConstraint: NSLayoutConstraint? {
        heightConstraints.first
    }

    var widthConstraint: NSLayoutConstraint? {
        widthConstraints.first
    }
}
