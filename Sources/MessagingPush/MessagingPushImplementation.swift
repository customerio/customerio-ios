import CioTracking
import Common
import Foundation
#if canImport(UserNotifications) && canImport(UIKit)
import UIKit
import UserNotifications
#endif

internal class MessagingPushImplementation: MessagingPushInstance {
    let siteId: SiteId
    let logger: Logger
    let jsonAdapter: JsonAdapter
    let sdkConfig: SdkConfig
    let backgroundQueue: Queue
    let sdkInitializedUtil: SdkInitializedUtil
    let deepLinkUtil: DeepLinkUtil
    let pushNotificationsUtil: PushNotificationsUtil

    private var customerIO: CustomerIO? {
        sdkInitializedUtil.customerio
    }

    /// testing init
    internal init(
        siteId: SiteId,
        logger: Logger,
        jsonAdapter: JsonAdapter,
        sdkConfig: SdkConfig,
        backgroundQueue: Queue,
        sdkInitializedUtil: SdkInitializedUtil,
        deepLinkUtil: DeepLinkUtil,
        pushNotificationsUtil: PushNotificationsUtil
    ) {
        self.siteId = siteId
        self.logger = logger
        self.jsonAdapter = jsonAdapter
        self.sdkConfig = sdkConfig
        self.backgroundQueue = backgroundQueue
        self.sdkInitializedUtil = sdkInitializedUtil
        self.deepLinkUtil = deepLinkUtil
        self.pushNotificationsUtil = pushNotificationsUtil
    }

    internal init(diGraph: DIGraph) {
        self.siteId = diGraph.siteId
        self.logger = diGraph.logger
        self.jsonAdapter = diGraph.jsonAdapter
        self.sdkConfig = diGraph.sdkConfig
        self.backgroundQueue = diGraph.queue
        self.sdkInitializedUtil = SdkInitializedUtilImpl()
        self.deepLinkUtil = diGraph.deepLinkUtil
        self.pushNotificationsUtil = diGraph.pushNotificationsUtil
    }

    func deleteDeviceToken() {
        customerIO?.deleteDeviceToken()
    }

    func registerDeviceToken(_ deviceToken: String) {
        customerIO?.registerDeviceToken(deviceToken)
    }

    func trackMetric(deliveryID: String, event: Metric, deviceToken: String) {
        customerIO?.trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken)
    }

    #if canImport(UserNotifications)
    func trackMetric(
        notificationContent: UNNotificationContent,
        event: Metric
    ) {
        guard let deliveryID: String = notificationContent.userInfo["CIO-Delivery-ID"] as? String,
              let deviceToken: String = notificationContent.userInfo["CIO-Delivery-Token"] as? String
        else {
            return
        }

        trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken)
    }

    // There are files that are created just for displaying a rich push. After a push is interacted with, those files
    // are no longer needed.
    // This function's job is to cleanup after a push is no longer being displayed.
    internal func cleanupAfterPushInteractedWith(pushContent: CustomerIOParsedPushPayload) {
        pushContent.cioAttachments.forEach { attachment in
            let localFilePath = attachment.url

            try? FileManager.default.removeItem(at: localFilePath)
        }
    }
    #endif
}

extension MessagingPushImplementation: PushNotificationPromptHook{
    func showPushNotificationPrompt(options : [String: Any], onComplete: @escaping (Bool?) -> Void) {
        pushNotificationsUtil.showPromptForPushNotificationPermission(options: options) { response in
                
            // TODO : Callback pending
            print(response)
            onComplete(true)
        }
    }
}
