import Foundation
import UIKit

// Callbacks specific to inline message events.
public protocol InlineMessageManagerDelegate: AnyObject {
    /// Called when the GistView's HTML content size changes
    func sizeChanged(width: CGFloat, height: CGFloat)

    /// Called when the inline message is closed (via a "close" action or similar)
    func onCloseAction()

    /**
     Called when any inline button/action is tapped.
     If your delegate handles the action completely and does not want any default handling, return `true`.
     Otherwise, return `false` so the manager's default logic is triggered.
     */
    func onInlineButtonAction(
        message: Message,
        currentRoute: String,
        action: String,
        name: String
    ) -> Bool

    /// Called when the inline message is about to change to a new template
    func willChangeMessage(newTemplateId: String)
}

/**
 A MessageManager subclass that displays an in-app message inline (embedded in a view).
 It inherits from BaseMessageManager so it shares the same engine/subscription logic
 as the modal flow. The main difference is how it's shown and dismissed:
    - Inline does not use a modal overlay; it is rendered inside your app's UI.
 */
public class InlineMessageManager: BaseMessageManager {
    // The GistView that can be placed inline in your UI.
    // Add this view to your own view hierarchy wherever you want the message to appear.
    public var inlineMessageView: GistView {
        // If no delegate is set yet, set ourselves as the GistViewDelegate
        if super.gistView.delegate == nil {
            super.gistView.delegate = self
        }
        return super.gistView
    }

    public weak var inlineMessageDelegate: InlineMessageManagerDelegate?

    // MARK: - Overriding Base Hooks

    override public func onMessageDisplayed() {
        // For an inline message, "onMessageDisplayed()" typically means
        // the content is loaded and we're ready to show the GistView in the layout.
        logger.logWithModuleTag(
            "Inline message displayed: \(currentMessage.describeForLogs)",
            level: .debug
        )
        // Inline messages don’t need to "present" a modal,
        // so there's nothing special to do here unless you want
        // to do extra logging, analytics, or UI hooks.
    }

    override func onMessageDismissed(
        messageState: MessageState
    ) {
        // For an inline message, "onMessageDismissed" means we should clean up:
        //  - Possibly remove inlineMessageView from its superview
        //  - Clean up engine, unsubscribe, etc.
        logger.logWithModuleTag(
            "Inline message dismissed: \(currentMessage.describeForLogs)",
            level: .debug
        )

        // Remove engine from memory
        removeEngineWebView()
        // Unsubscribe from store updates
        unsubscribeFromInAppMessageState()

        // If the message was explicitly dismissed (as opposed to reset to .initial),
        // we can fetch the next message in the queue
        if case .dismissed = messageState {
            gist.fetchUserMessagesFromRemoteQueue()
        }
    }

    // MARK: - Additional Inline Logic

    /**
     If you'd like to manually dismiss the inline message (for instance,
     in response to a user action in your app's UI), you can call this.
     It triggers the normal in-app dismissal logic in the store.
     */
    public func closeInlineMessage() {
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
        // Notify delegate that the inline content size has changed
        inlineMessageDelegate?.sizeChanged(width: width, height: height)
    }

    public func action(
        message: Message,
        currentRoute: String,
        action: String,
        name: String
    ) {
        // Before passing the action to the base logic,
        // let the InlineMessageManagerDelegate try to handle it first.
        let didHandle = inlineMessageDelegate?.onInlineButtonAction(
            message: message,
            currentRoute: currentRoute,
            action: action,
            name: name
        ) ?? false

        // If the delegate did not handle it,
        // we can still dispatch it through `inAppMessageManager`.
        // For example, to log the tap or handle normal fallback.
        if !didHandle {
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
        }
    }
}
