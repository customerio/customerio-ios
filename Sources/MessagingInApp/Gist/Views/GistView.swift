import CioInternalCommon
import Foundation
import UIKit

public protocol GistViewDelegate: AnyObject {
    func action(message: Message, currentRoute: String, action: String, name: String)
    func sizeChanged(message: Message, width: CGFloat, height: CGFloat)
}

/// Delegate protocol for handling view lifecycle events for GistView
public protocol GistViewLifecycleDelegate: AnyObject {
    /// Called when the GistView is about to be removed from its superview
    func gistViewWillRemoveFromSuperview(_ gistView: GistView)
}

public class GistView: UIView {
    public weak var delegate: GistViewDelegate?
    public weak var lifecycleDelegate: GistViewLifecycleDelegate?
    var message: Message?

    convenience init(message: Message, engineView: UIView) {
        self.init()
        self.message = message
        addSubview(engineView)
        engineView.autoresizingMask = [.flexibleWidth, .flexibleHeight, .flexibleBottomMargin, .flexibleRightMargin]
    }

    override public func removeFromSuperview() {
        super.removeFromSuperview()

        // Notify lifecycle delegate that this view is being removed
        // The delegate (InlineMessageManager or ModalMessageManager) can decide
        // what action to take based on the context
        lifecycleDelegate?.gistViewWillRemoveFromSuperview(self)
    }
}
