import CioInternalCommon
import Foundation
#if canImport(UserNotifications) && canImport(UIKit)
import UIKit
import UserNotifications
#endif

class MessagingPushImplementation: MessagingPushInstance {
    var moduleConfig: MessagingPushConfigOptions
    let logger: Logger

    /// testing init
    init(
        moduleConfig: MessagingPushConfigOptions,
        logger: Logger
    ) {
        self.moduleConfig = moduleConfig
        self.logger = logger
    }

    init(diGraph: DIGraphShared, moduleConfig: MessagingPushConfigOptions) {
        self.moduleConfig = moduleConfig
        self.logger = diGraph.logger
    }
    
    func configure(with configureHandler: @escaping ((inout MessagingPushConfigOptions) -> Void)) {
        var newConfig = moduleConfig
        configureHandler(&newConfig)
        moduleConfig.apply(newConfig)
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
