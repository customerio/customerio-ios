import CioInternalCommon
import Foundation
#if canImport(UserNotifications) && canImport(UIKit)
import UIKit
import UserNotifications
#endif

class MessagingPushImplementation: MessagingPushInstance {
    let logger: Logger
    let jsonAdapter: JsonAdapter
    let moduleConfig: MessagingPushConfigOptions
    let backgroundQueue: Queue

    /// testing init
    init(
        logger: Logger,
        jsonAdapter: JsonAdapter,
        moduleConfig: MessagingPushConfigOptions,
        backgroundQueue: Queue
    ) {
        self.logger = logger
        self.jsonAdapter = jsonAdapter
        self.moduleConfig = moduleConfig
        self.backgroundQueue = backgroundQueue
    }

    init(diGraph: DIGraph, moduleConfig: MessagingPushConfigOptions) {
        self.logger = diGraph.logger
        self.jsonAdapter = diGraph.jsonAdapter
        self.moduleConfig = moduleConfig
        self.backgroundQueue = diGraph.queue
    }

    func deleteDeviceToken() {
        // FIXME: [CDP] Pass to Journey
        // customerIO?.deleteDeviceToken()
    }

    func registerDeviceToken(_ deviceToken: String) {
        // FIXME: [CDP] Pass to Journey
        // customerIO?.registerDeviceToken(deviceToken)
    }

    func trackMetric(deliveryID: String, event: Metric, deviceToken: String) {
        // FIXME: [CDP] Pass to Journey
        // customerIO?.trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken)
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
    func cleanupAfterPushInteractedWith(pushContent: CustomerIOParsedPushPayload) {
        pushContent.cioAttachments.forEach { attachment in
            let localFilePath = attachment.url

            try? FileManager.default.removeItem(at: localFilePath)
        }
    }
    #endif
}
