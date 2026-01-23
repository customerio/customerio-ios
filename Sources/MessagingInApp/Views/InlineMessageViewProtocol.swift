import Foundation
import UIKit

/// Base protocol for inline message container views that provides common functionality for displaying in-app messages.
protocol InlineMessageViewProtocol: GistInlineMessageUIViewDelegate {}

/// Shared functionality for creating and managing inline message views.
extension InlineMessageViewProtocol {
    /// Creates and configures a new `GistInlineMessageUIView` instance with this view as delegate.
    func createGistMessageView(elementId: String) -> GistInlineMessageUIView {
        let inlineInAppMessageView = GistInlineMessageUIView(elementId: elementId)
        inlineInAppMessageView.delegate = self
        return inlineInAppMessageView
    }
}

/// UIView-specific functionality for inline message containers.
extension InlineMessageViewProtocol where Self: UIView {
    /// The underlying Gist inline message view that renders the actual content.
    var inAppMessageView: GistInlineMessageUIView? {
        subviews.compactMap { $0 as? GistInlineMessageUIView }.first
    }
}
