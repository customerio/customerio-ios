@testable import CioMessagingInApp
import Foundation
import UIKit

class ViewAnimationRunnerStub: ViewAnimationRunner {
    // If you want to have full control over when an animation finishes, add a closure and call the completion handler when the animation should finish.
    // Great for tests where you want to begin an aimation, run some logic, and finish the animation.
    var animateClosure: ((() -> Void) -> Void)?

    func animate(withDuration duration: TimeInterval, delay: TimeInterval, options: UIView.AnimationOptions, animations: @escaping () -> Void, completion: ((Bool) -> Void)?) {
        if let animateClosure = animateClosure {
            animateClosure {
                completion?(true)
            }
        } else {
            completion?(true)
        }
    }
}
