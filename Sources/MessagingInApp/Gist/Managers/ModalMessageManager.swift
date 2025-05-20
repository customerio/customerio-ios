import Foundation
import UIKit

/// A MessageManager subclass that specifically shows messages in a modal view.
public class ModalMessageManager: BaseMessageManager {
    private var modalViewManager: ModalViewManager?
    var inAppMessageStoreSubscriber: InAppMessageStoreSubscriber?
    override init(state: InAppMessageState, message: Message) {
        super.init(state: state, message: message)
        subscribeToInAppMessageState()
    }

    deinit {
        unsubscribeFromInAppMessageState()
    }

    // MARK: - Subscription to InAppMessageState

    public func subscribeToInAppMessageState() {
        inAppMessageStoreSubscriber = {
            let subscriber = InAppMessageStoreSubscriber { [self] state in
                let messageState = state.modalMessageState
                switch messageState {
                case .displayed:
                    threadUtil.runMain {
                        // Subclasses (Modal or Inline) can show differently
                        self.onMessageDisplayed()
                    }
                case .dismissed, .initial:
                    threadUtil.runMain {
                        // Dismiss the message from subclass
                        self.onMessageDismissed(messageState: messageState)
                    }
                default:
                    break
                }
            }
            self.inAppMessageManager.subscribe(keyPath: \.modalMessageState, subscriber: subscriber)
            return subscriber
        }()
    }

    // Show the modal when the message is displayed
    func onMessageDisplayed() {
        guard isMessageLoaded else {
            logger.logWithModuleTag(
                "Message not loaded yet. Skipping loadModalMessage for \(currentMessage.describeForLogs).",
                level: .debug
            )
            return
        }

        logger.logWithModuleTag(
            "Displaying modal message: \(currentMessage.describeForLogs)",
            level: .debug
        )
        
        // Set lifecycle delegate to handle removeFromSuperview event correctly for modal context
        gistView.lifecycleDelegate = self

        let gistProperties = currentMessage.gistProperties
        modalViewManager = ModalViewManager(
            gistView: gistView,
            position: gistProperties.position,
            overlayColor: gistProperties.overlayColor
        )
        // Show the modal with an optional completion
        modalViewManager?.showModalView { [weak self] in
            self?.elapsedTimer.end()
        }
    }

    // Called when the message is dismissed (or reset).
    // Because onMessageDismissed(...) is internal in BaseMessageManager,
    // we can override it here in the same module.
    func onMessageDismissed(messageState: ModalMessageState) {
        logger.logWithModuleTag(
            "Dismissing message: \(currentMessage.describeForLogs) from ModalMessageManager",
            level: .debug
        )

        // Common handler to finalize dismissal logic
        let dismissalHandler: () -> Void = { [weak self] in
            self?.finishDismissal(messageState: messageState)
        }

        guard let modalViewManager = modalViewManager else {
            // No modal to dismiss
            dismissalHandler()
            return
        }
        // Dismiss the modal then call completion
        modalViewManager.dismissModalView(completionHandler: dismissalHandler)
    }

    open func unsubscribeFromInAppMessageState() {
        guard let subscriber = inAppMessageStoreSubscriber else { return }
        logger.logWithModuleTag("Unsubscribing BaseMessageManager from InAppMessageState", level: .debug)
        inAppMessageManager.unsubscribe(subscriber: subscriber)
        inAppMessageStoreSubscriber = nil
    }

    private func finishDismissal(messageState: ModalMessageState) {
        removeEngineWebView()
        unsubscribeFromInAppMessageState()

        // If the message was explicitly dismissed (not just reset to initial)
        // then fetch next messages from queue
        if case .dismissed = messageState {
            gist.fetchUserMessagesFromRemoteQueue()
        }
    }

    /// Optional public method to kick off modal display timing or logs.
    /// (Used in some flows to explicitly measure "show time".)
    public func showMessage() {
        elapsedTimer.start(
            title: "Displaying modal for message: \(currentMessage.messageId)"
        )
    }
}

// MARK: - GistViewLifecycleDelegate

extension ModalMessageManager: GistViewLifecycleDelegate {
    /// For modal messages, we don't want to automatically dismiss when the view is removed from superview
    /// because the modal dismissal is handled by the ModalViewManager and state system
    public func gistViewWillRemoveFromSuperview(_ gistView: GistView) {
        logger.logWithModuleTag(
            "GistView being removed from superview for modal message: \(currentMessage.describeForLogs). No action taken.",
            level: .debug
        )
        // Intentionally not triggering dismissMessage() since modal dismissal is managed differently
    }
}
