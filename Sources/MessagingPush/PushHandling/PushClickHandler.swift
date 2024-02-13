import CioInternalCommon
import Foundation
import UserNotifications

@available(iOSApplicationExtension, unavailable)
protocol PushClickHandler: AutoMockable {
    func pushClicked(_ push: PushNotification)
}

@available(iOSApplicationExtension, unavailable)
// sourcery: InjectRegisterShared = "PushClickHandler"
class PushClickHandlerImpl: PushClickHandler {
    private let deepLinkUtil: DeepLinkUtil
    private let messagingPush: MessagingPushInstance

    init(deepLinkUtil: DeepLinkUtil, messagingPush: MessagingPushInstance) {
        self.deepLinkUtil = deepLinkUtil
        self.messagingPush = messagingPush
    }

    // Note: This function is called from automatic and manual push click handlers.
    func pushClicked(_ push: PushNotification) {
        guard let cioDelivery = push.cioDelivery else {
            return
        }

        messagingPush.trackMetric(deliveryID: cioDelivery.id, event: .opened, deviceToken: cioDelivery.token)

        // Cleanup files on device that were used when the push was displayed. Files are no longer
        // needed now that the push is no longer shown.
        cleanupAfterPushInteractedWith(push: push)

        // Handle deep link, if there is one attached to push.
        if let deepLinkUrl = push.cioDeepLink?.url {
            deepLinkUtil.handleDeepLink(deepLinkUrl)
        }
    }

    // There are files that are created just for displaying a rich push. After a push is interacted with, those files
    // are no longer needed.
    // This function's job is to cleanup after a push is no longer being displayed.
    func cleanupAfterPushInteractedWith(push: PushNotification) {
        push.cioAttachments.forEach { attachment in
            let localFilePath = attachment.localFileUrl

            try? FileManager.default.removeItem(at: localFilePath)
        }
    }
}
