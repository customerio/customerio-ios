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
    var onTraitCollectionChange: ((UITraitCollection) -> Void)?
    var message: Message?

    /// Creates a Gist view with the specified frame.
    override public init(frame: CGRect) {
        super.init(frame: frame)
        registerForInterfaceStyleChanges()
    }

    /// Creates a Gist view from an archived interface description.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForInterfaceStyleChanges()
    }

    convenience init(message: Message, engineView: UIView) {
        self.init(frame: .zero)
        self.message = message
        addSubview(engineView)
        engineView.autoresizingMask = [.flexibleWidth, .flexibleHeight, .flexibleBottomMargin, .flexibleRightMargin]
    }

    private func registerForInterfaceStyleChanges() {
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: GistView, _: UITraitCollection) in
                view.onTraitCollectionChange?(view.traitCollection)
            }
        }
    }

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if #unavailable(iOS 17.0),
           traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            onTraitCollectionChange?(traitCollection)
        }
    }

    override public func removeFromSuperview() {
        super.removeFromSuperview()

        // Notify lifecycle delegate that this view is being removed
        // The delegate (InlineMessageManager or ModalMessageManager) can decide
        // what action to take based on the context
        lifecycleDelegate?.gistViewWillRemoveFromSuperview(self)
    }
}
