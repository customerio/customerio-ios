import Foundation
import UIKit

/**
 Class that implements the business logic for a modal message being displayed. Handle when action buttons are clicked, render the HTML message, and get callbacks for modal message events.
 */
class ModalMessageManager: MessageManager {
    private var messageLoaded = false
    private var modalViewManager: ModalViewManager?
    var messagePosition: MessagePosition = .top

    func showMessage(position: MessagePosition) {
        messagePosition = position
    }

    override func onDoneLoadingMessage(routeLoaded: String, onComplete: @escaping () -> Void) {
        if routeLoaded == currentMessage.messageId, !messageLoaded {
            messageLoaded = true

            if UIApplication.shared.applicationState == .active {
                modalViewManager = ModalViewManager(gistView: gistView, position: messagePosition)
                modalViewManager?.showModalView {
                    onComplete()
                }
            } else {
                Gist.shared.removeMessageManager(instanceId: currentMessage.instanceId)
            }
        }
    }

    override func onDeepLinkOpened() {
        dismissMessage()
    }

    override func onCloseAction() {
        removePersistentMessage()
        dismissMessage()
    }

    func removePersistentMessage() {
        if currentMessage.gistProperties.persistent == true {
            Logger.instance.debug(message: "Persistent message dismissed, logging view")
            Gist.shared.logMessageView(message: currentMessage)
        }
    }

    func dismissMessage(completionHandler: (() -> Void)? = nil) {
        if let modalViewManager = modalViewManager {
            modalViewManager.dismissModalView { [weak self] in
                guard let self = self else { return }
                self.delegate?.messageDismissed(message: self.currentMessage)
                completionHandler?()
            }
        }
    }

    override func onReplaceMessage(newMessageToShow: Message) {
        dismissMessage {
            _ = Gist.shared.showMessage(newMessageToShow)
        }
    }
}
