import Foundation
import UIKit

/// A MessageManager subclass that specifically shows messages in a modal view.
public class ModalMessageManager: BaseMessageManager {
    private var modalViewManager: ModalViewManager?

    override init(state: InAppMessageState, message: Message) {
        super.init(state: state, message: message)
        subscribeToInAppMessageState()
    }

    // MARK: - Subscription to InAppMessageState

    public func subscribeToInAppMessageState() {
        inAppMessageStoreSubscriber = {
            let subscriber = InAppMessageStoreSubscriber { [self] state in
                let messageState = state.currentMessageState
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
            self.inAppMessageManager.subscribe(keyPath: \.currentMessageState, subscriber: subscriber)
            return subscriber
        }()
    }

    // Show the modal when the message is displayed
    override public func onMessageDisplayed() {
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
    override func onMessageDismissed(messageState: ModalMessageState) {
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
