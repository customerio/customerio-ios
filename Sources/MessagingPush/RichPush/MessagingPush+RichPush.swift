import CioTracking
import Common
import Foundation
#if canImport(UserNotifications) && canImport(UIKit)
import UIKit
import UserNotifications
#endif

public extension MessagingPush {
    #if canImport(UserNotifications)
    /**
     - returns:
     Bool indicating if this push notification is one handled by Customer.io SDK or not.
     If function returns `false`, `contentHandler` will *not* be called by the SDK.
     */
    @discardableResult
    func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) -> Bool {
        guard let implementation = implementation else {
            contentHandler(request.content)
            return false
        }

        return implementation.didReceive(request, withContentHandler: contentHandler)
    }

    /**
     iOS telling the notification service to hurry up and stop modifying the push notifications.
     Stop all network requests and modifying and show the push for what it looks like now.
     */
    func serviceExtensionTimeWillExpire() {
        implementation?.serviceExtensionTimeWillExpire()
    }
    #endif
}

extension MessagingPushImplementation {
    #if canImport(UserNotifications)
    /**
     - returns:
     Bool indicating if this push notification is one handled by Customer.io SDK or not.
     If function returns `false`, `contentHandler` will *not* be called by the SDK.
     */
    @discardableResult
    func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) -> Bool {
        logger.info("did recieve notification request. Checking if message was a rich push sent from Customer.io...")
        logger.debug("notification request: \(request.content.userInfo)")

        if sdkConfig.autoTrackPushEvents,
           let deliveryID: String = request.content.userInfo["CIO-Delivery-ID"] as? String,
           let deviceToken: String = request.content.userInfo["CIO-Delivery-Token"] as? String {
            logger.info("automatically tracking push metric: delivered")
            logger.debug("parsed deliveryId \(deliveryID), deviceToken: \(deviceToken)")

            trackMetric(deliveryID: deliveryID, event: .delivered, deviceToken: deviceToken)
        }

        guard let pushContent = CustomerIOParsedPushPayload.parse(
            notificationContent: request.content,
            jsonAdapter: jsonAdapter
        )
        else {
            // push does not contain a CIO rich payload, so end early
            logger.info("the notification was not sent by Customer.io. Ignoring notification request.")
            return false
        }

        logger
            .info("""
            the notification was sent by Customer.io.
            Parsing notification request to display rich content such as images, deep links, etc.
            """)
        logger.debug("push content: \(pushContent)")

        RichPushRequestHandler.shared.startRequest(
            request,
            content: pushContent,
            siteId: siteId
        ) { [weak self] notificationContent in
            self?.logger.debug("rich push was composed.")

            self?.logger
                .debug(
                    "running all background queue tasks and waiting until complete to prevent OS from killing notification service extension before all HTTP requests have been performed"
                )
            self?.backgroundQueue.run {
                self?.logger.debug("all background queue tasks done running. rich push processing is done!")
                contentHandler(notificationContent)
            }
        }

        return true
    }

    /**
     iOS telling the notification service to hurry up and stop modifying the push notifications.
     Stop all network requests and modifying and show the push for what it looks like now.
     */
    func serviceExtensionTimeWillExpire() {
        logger.info("notification service time will expire. Stopping all notification requests early.")

        RichPushRequestHandler.shared.stopAll()
    }
    #endif
}
