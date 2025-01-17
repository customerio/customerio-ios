import Foundation
import UIKit

/// A MessageManager subclass that specifically shows messages in a modal view.
public class ModalMessageManager: BaseMessageManager {
    private var modalViewManager: ModalViewManager?

    override public func onMessageDisplayed() {
        // The original "loadModalMessage()" logic
        // but triggered by `onMessageDisplayed()`
        guard isMessageLoaded else {
            logger.logWithModuleTag("Message not loaded yet. Skipping loadModalMessage.", level: .debug)
            return
        }

        logger.logWithModuleTag("Loading modal message: \(currentMessage.describeForLogs)", level: .debug)
        let gistProperties = currentMessage.gistProperties
        modalViewManager = ModalViewManager(
            gistView: gistView,
            position: gistProperties.position,
            overlayColor: gistProperties.overlayColor
        )
        modalViewManager?.showModalView { [weak self] in
            self?.elapsedTimer.end()
        }
    }

    override func onMessageDismissed(messageState: MessageState) {
        logger.logWithModuleTag("Dismissing message: \(currentMessage.describeForLogs) from ModalMessageManager", level: .debug)

        guard let modalViewManager = modalViewManager else {
            // No modal to dismiss
            finishDismissal(messageState: messageState)
            return
        }

        // Dismiss the modal then call completion
        modalViewManager.dismissModalView { [weak self] in
            self?.finishDismissal(messageState: messageState)
        }
    }

    private func finishDismissal(messageState: MessageState) {
        removeEngineWebView()
        unsubscribeFromInAppMessageState()

        // If the message was explicitly dismissed (not just reset to initial)
        // then fetch next messages from queue
        if case .dismissed = messageState {
            gist.fetchUserMessagesFromRemoteQueue()
        }
    }

    public func showMessage() {
        // Original `showMessage()` logic
        elapsedTimer.start(title: "Displaying modal for message: \(currentMessage.messageId)")
    }
}
