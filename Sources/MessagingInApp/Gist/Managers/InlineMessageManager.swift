import CioInternalCommon
import Foundation
import UIKit

// MARK: - InlineMessageManagerDelegate

/// Callbacks specific to inline message events.
protocol InlineMessageManagerDelegate: AnyObject {
    /// Called when the inline web message (HTML) size changes
    func sizeChanged(width: CGFloat, height: CGFloat)
    /// Called when the inline message is closed (via a "close" action)
    func onCloseAction()
    /**
     Called when an inline button or link is tapped.
     Return `true` if your delegate handled the action entirely (so the manager does nothing more).
     Return `false` if you'd like the manager to continue its normal flow.
     */
    func onInlineButtonAction(
        message: Message,
        currentRoute: String,
        action: String,
        name: String
    ) -> Bool
    /// Called when the inline message is about to change to a new template (if supported)
    func willChangeMessage(newTemplateId: String)
}

// MARK: - InlineMessageManager

/// A `BaseMessageManager` subclass that displays an in-app message inline (embedded in your UI).
/// Rather than presenting a modal, it uses a `GistView` that you place in a view hierarchy.
class InlineMessageManager: BaseMessageManager {
    public weak var inlineMessageDelegate: InlineMessageManagerDelegate?

    // Expose the GistView for embedding.
    // Also set ourselves as the GistViewDelegate if not already set.
    public var inlineMessageView: GistView {
        if gistView.delegate == nil {
            gistView.delegate = self
        }
        return gistView
    }

    // swiftlint:disable todo
    // TODO: Verify and implement the method.
    // swiftlint:enable todo
    func stopAndCleanup() {}

    // MARK: - Overriding from Base

    /// Called when the in-app state changes to `.displayed`.
    /// Inline typically means the content is ready and the `inlineMessageView` is or can be added to the UI.
    override public func onMessageDisplayed() {
        logger.logWithModuleTag(
            "Inline message displayed: \(currentMessage.describeForLogs)",
            level: .debug
        )
        // If needed, you might notify your delegate that it's displayed or ready.
        // e.g., inlineMessageDelegate?.didDisplayInlineMessage?()
    }

    /// Called when the message is dismissed (or reset).
    /// Typically remove the web engine, unsubscribe, and optionally remove the inline view.
    override func onMessageDismissed(messageState: ModalMessageState) {
        logger.logWithModuleTag(
            "Inline message dismissed: \(currentMessage.describeForLogs)",
            level: .debug
        )

        removeEngineWebView()

        // If the message was explicitly dismissed, fetch new messages from queue
        if case .dismissed = messageState {
            gist.fetchUserMessagesFromRemoteQueue()
        }
    }

    // MARK: - Additional Inline Logic

    /// Manually closes the inline message (for example, if your app’s UI has a "Close" button).
    /// This will trigger the normal in-app dismissal flow,
    /// which eventually calls `onMessageDismissed(messageState:)`.
    public func closeInlineMessage() {
        // Notify delegate that a close action occurred
        inlineMessageDelegate?.onCloseAction()

        // Trigger the store to dismiss
        inAppMessageManager.dispatch(
            action: .dismissMessage(
                message: currentMessage,
                viaCloseAction: true
            )
        )
    }
}

// MARK: - GistViewDelegate

extension InlineMessageManager: GistViewDelegate {
    public func sizeChanged(message: Message, width: CGFloat, height: CGFloat) {
        // Pass the size change event to the inlineMessageDelegate
        inlineMessageDelegate?.sizeChanged(width: width, height: height)
    }

    public func action(
        message: Message,
        currentRoute: String,
        action: String,
        name: String
    ) {
        // Let the inlineMessageDelegate have a chance to handle the action
        guard let delegate = inlineMessageDelegate,
              delegate.onInlineButtonAction(
                  message: message,
                  currentRoute: currentRoute,
                  action: action,
                  name: name
              )
        else {
            // If no delegate or delegate didn't handle it, pass to in-app manager
            inAppMessageManager.dispatch(
                action: .engineAction(
                    action: .tap(
                        message: message,
                        route: currentRoute,
                        name: name,
                        action: action
                    )
                )
            )
            return
        }
    }

    /// If your app uses multiple message templates and may switch to a new template ID,
    /// you can forward that event here if the `GistView` notifies you:
    public func willChangeMessage(newTemplateId: String) {
        inlineMessageDelegate?.willChangeMessage(newTemplateId: newTemplateId)
    }
}
