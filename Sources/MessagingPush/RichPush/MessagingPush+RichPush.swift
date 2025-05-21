import CioInternalCommon
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
        let push = UNNotificationWrapper(notificationRequest: request)
        pushLogger.logReceivedPushMessage(notification: push)

        guard let pushCioDeliveryInfo = push.cioDelivery else {
            pushLogger.logReceivedNonCioPushMessage()
            return false
        }

        pushLogger.logReceivedCioPushMessage()

        if moduleConfig.autoTrackPushEvents {
            pushLogger.logTrackingPushMessageDelivered(deliveryId: pushCioDeliveryInfo.id)

            trackMetricFromNSE(deliveryID: pushCioDeliveryInfo.id, event: .delivered, deviceToken: pushCioDeliveryInfo.token)
        } else {
            pushLogger.logPushMetricsAutoTrackingDisabled()
        }

        RichPushRequestHandler.shared.startRequest(
            push: push
        ) { composedRichPush in
            self.logger.debug("rich push was composed \(composedRichPush).")

            // This conditional will only work in production and not in automated tests. But this file cannot be in automated tests so this conditional is OK for now.
            if let composedRichPush = composedRichPush as? UNNotificationWrapper {
                self.logger.info("Customer.io push processing is done!")
                contentHandler(composedRichPush.notificationContent)
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
