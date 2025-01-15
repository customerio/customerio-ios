import CioInternalCommon
import Foundation
import UIKit

class ModalMessageManager: BaseMessageManager {
    private var modalViewManager: ModalViewManager?
    private var messageLoaded = false
    var messagePosition: MessagePosition = .top

    override func handleMessageLoaded() {
        super.handleMessageLoaded()

        // Only handle first time message is loaded
        if currentRoute == currentMessage.messageId, !messageLoaded {
            messageLoaded = true

            guard UIApplication.shared.applicationState == .active else {
                dismissMessage()
                return
            }

            setupAndShowModal()
        }
    }

    override func cleanup() {
        super.cleanup()
    }

    func showMessage(position: MessagePosition) {
        messagePosition = position
        if messageLoaded {
            setupAndShowModal()
        }
    }

    override func dismissMessage(completion: (() -> Void)? = nil) {
        guard let modalViewManager = modalViewManager else {
            completion?()
            return
        }

        modalViewManager.dismissModalView { [weak self] in
            guard let self = self else { return }
            self.delegate?.messageDismissed(message: self.currentMessage)
            completion?()
        }
    }

    private func setupAndShowModal() {
        let gistProperties = currentMessage.gistProperties
        modalViewManager = ModalViewManager(
            gistView: gistView,
            position: messagePosition,
            overlayColor: gistProperties.overlayColor
        )

        modalViewManager?.showModalView { [weak self] in
            guard let self = self else { return }
            self.delegate?.messageShown(message: self.currentMessage)
        }
    }

    override func onDeepLinkOpened() {
        super.onDeepLinkOpened()
        dismissMessage()
    }

    override func onTapAction(message: Message, currentRoute: String, action: String, name: String) {
        super.onTapAction(message: message, currentRoute: currentRoute, action: action, name: name)
        delegate?.action(message: message, currentRoute: currentRoute, action: action, name: name)
    }
}
