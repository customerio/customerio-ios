import CioInternalCommon
import Foundation
import UIKit

/// Delegate protocol for handling inline message bridge view events.
/// Designed for cross-platform wrapper implementations (React Native, Flutter).
public protocol InlineMessageBridgeViewDelegate: AnyObject, AutoMockable {
    /// Called when a custom action button is tapped in an inline message.
    /// - Returns: Boolean indicating if the action was handled
    func onActionClick(message: InAppMessage, actionValue: String, actionName: String) -> Bool

    /// Called when a message has been rendered with specific dimensions.
    func onMessageSizeChanged(width: CGFloat, height: CGFloat)

    /// Called when there is no message available to display.
    func onNoMessageToDisplay()

    /// Called when message loading begins.
    func onStartLoading(onComplete: @escaping () -> Void)

    /// Called when message loading finishes.
    func onFinishLoading()
}

/// A bridge view for inline in-app messages designed for cross-platform integration.
/// This view delegates all rendering and interaction handling to wrapper implementations
/// such as React Native or Flutter, providing a bridge between the native SDK and wrapper frameworks.
///
/// Usage:
/// ```swift
/// let bridgeView = InlineMessageBridgeView()
/// bridgeView.attachToParent(parent: parentView, delegate: delegateImpl)
/// bridgeView.elementId = "elementId"
/// ```
public class InlineMessageBridgeView: UIView, InlineMessageViewProtocol {
    /// The element ID used to identify which inline message to display.
    /// Setting this property triggers view setup.
    public var elementId: String? {
        didSet {
            setupInlineMessageView()
        }
    }

    /// Delegate for handling wrapper-specific events and interactions.
    public weak var delegate: InlineMessageBridgeViewDelegate?

    /// Cached width of the last rendered message to prevent unnecessary updates.
    private var lastRenderedWidth: CGFloat?

    /// Cached height of the last rendered message to prevent unnecessary updates.
    private var lastRenderedHeight: CGFloat?

    /// Initializes a new inline message bridge view.
    public init() {
        super.init(frame: .zero)
    }

    /// InlineMessageBridgeView does not support Interface Builder initialization.
    /// Use `init()` instead.
    required init?(coder: NSCoder) {
        assertionFailure(
            "InlineMessageBridgeView does not support initialization from Interface Builder. Use init() instead."
        )
        return nil
    }

    deinit {
        onViewDetached()
    }

    /// Attaches this view to a parent view and sets the delegate.
    /// Called once from wrapper constructor to establish the view hierarchy.
    /// - Parameters:
    ///   - parent: The parent view to attach this wrapper to
    ///   - delegate: The delegate for handling wrapper events
    public func attachToParent(parent: UIView, delegate: InlineMessageBridgeViewDelegate) {
        self.delegate = delegate
        constrainToFillParent(parent)
    }

    /// Called every time the wrapper view is attached to a screen.
    /// May be called multiple times during the wrapper's lifecycle.
    public func onViewAttached() {
        setupInlineMessageView()
    }

    /// Called every time the wrapper view is detached from a screen.
    /// Cleans up resources to prevent memory leaks.
    public func onViewDetached() {
        inAppMessageView?.teardownView()
    }

    /// Sets up the underlying Gist inline message view if needed.
    private func setupInlineMessageView() {
        guard let elementId else {
            return // No element ID set, nothing to setup
        }

        // If view already exists, just update the element ID
        if let existingView = inAppMessageView {
            existingView.elementId = elementId
            return
        }

        // Create new inline message view
        let inlineInAppMessageView = createGistMessageView(elementId: elementId)
        inlineInAppMessageView.constrainToFillParent(self)
    }

    // MARK: - GistInlineMessageUIViewDelegate Implementation

    public func onMessageRendered(width: CGFloat, height: CGFloat) {
        // Prevent unnecessary updates if dimensions haven't changed to avoid flicker
        guard let inAppMessageView = inAppMessageView,
              !(lastRenderedWidth == width && lastRenderedHeight == height)
        else {
            return
        }

        // Update cached dimensions and show the rendered message
        lastRenderedWidth = width
        lastRenderedHeight = height
        inAppMessageView.isHidden = false

        // Notify delegate of the rendered message dimensions
        delegate?.onMessageSizeChanged(width: width, height: height)
        delegate?.onFinishLoading()
    }

    public func onNoMessageToDisplay() {
        delegate?.onMessageSizeChanged(width: 0, height: 0)
        delegate?.onNoMessageToDisplay()
        lastRenderedWidth = nil
        lastRenderedHeight = nil
    }

    public func onInlineButtonAction(
        message: Message, currentRoute: String, action: String, name: String
    ) -> Bool {
        delegate?.onActionClick(
            message: InAppMessage(gistMessage: message), actionValue: action, actionName: name
        ) ?? false
    }

    public func willChangeMessage(newTemplateId: String, onComplete: @escaping () -> Void) {
        delegate?.onStartLoading(onComplete: onComplete) ?? onComplete()
    }
}

// MARK: - UIView Extension

private extension UIView {
    /// Adds this view to the parent and constrains it to fill all edges with optional insets.
    /// - Parameters:
    ///   - parent: The parent view to add this view to and constrain against
    ///   - insets: Edge insets to apply when constraining (default is zero)
    func constrainToFillParent(_ parent: UIView, insets: UIEdgeInsets = .zero) {
        parent.addSubview(self)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parent.topAnchor, constant: insets.top),
            leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -insets.right),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -insets.bottom)
        ])
    }
}
