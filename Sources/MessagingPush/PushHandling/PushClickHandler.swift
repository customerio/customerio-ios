import CioInternalCommon
import CioTracking
import Foundation
import UserNotifications

@available(iOSApplicationExtension, unavailable)
protocol PushClickHandler: AutoMockable {
    func pushClicked(_ push: CustomerIOParsedPushPayload)
}

@available(iOSApplicationExtension, unavailable)
// sourcery: InjectRegister = "PushClickHandler"
class PushClickHandlerImpl: PushClickHandler {
    private let sdkConfig: SdkConfig
    private let deepLinkUtil: DeepLinkUtil
    private let customerIO: CustomerIOInstance

    init(sdkConfig: SdkConfig, deepLinkUtil: DeepLinkUtil, customerIO: CustomerIOInstance) {
        self.sdkConfig = sdkConfig
        self.deepLinkUtil = deepLinkUtil
        self.customerIO = customerIO
    }

    func pushClicked(_ parsedPush: CustomerIOParsedPushPayload) {
        // Track metrics
        if sdkConfig.autoTrackPushEvents {
            customerIO.trackMetric(deliveryID: parsedPush.deliveryId, event: .opened, deviceToken: parsedPush.deviceToken)
        }

        // Cleanup files on device that were used when the push was displayed. Files are no longer
        // needed now that the push is no longer shown.
        cleanupAfterPushInteractedWith(pushContent: parsedPush)

        // Handle deep link, if there is one attached to push.
        if let deepLinkUrl = parsedPush.deepLink {
            deepLinkUtil.handleDeepLink(deepLinkUrl)
        }
    }

    // There are files that are created just for displaying a rich push. After a push is interacted with, those files
    // are no longer needed.
    // This function's job is to cleanup after a push is no longer being displayed.
    func cleanupAfterPushInteractedWith(pushContent: CustomerIOParsedPushPayload) {
        pushContent.cioAttachments.forEach { attachment in
            let localFilePath = attachment.url

            try? FileManager.default.removeItem(at: localFilePath)
        }
    }
}
