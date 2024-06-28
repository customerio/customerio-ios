import CioInternalCommon
import Foundation
import UIKit

// Wrapper around UIKit animation functions to allow us to disable animations in tests.
protocol ViewAnimationRunner: AutoMockable {
    // function signature is identical to UIKit's UIView.animate() function.
    func animate(withDuration duration: TimeInterval, delay: TimeInterval, options: UIView.AnimationOptions, animations: @escaping () -> Void, completion: ((Bool) -> Void)?)
}

// sourcery: InjectRegisterShared = "ViewAnimationRunner"
class ViewAnimationRunnerImpl: ViewAnimationRunner {
    func animate(withDuration duration: TimeInterval, delay: TimeInterval, options: UIView.AnimationOptions = [], animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        UIView.animate(withDuration: duration, delay: delay, options: options, animations: animations, completion: completion)
    }
}
