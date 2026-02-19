import CioInternalCommon
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

class MessagingPushImplementation: MessagingPushInstance {
    let moduleConfig: MessagingPushConfigOptions
    let logger: Logger
    let pushLogger: PushNotificationLogger
    let jsonAdapter: JsonAdapter
    let eventBusHandler: EventBusHandler

    init(diGraph: DIGraphShared, moduleConfig: MessagingPushConfigOptions) {
        self.moduleConfig = moduleConfig
        self.logger = diGraph.logger
        self.jsonAdapter = diGraph.jsonAdapter
        self.eventBusHandler = diGraph.eventBusHandler
        self.pushLogger = diGraph.pushNotificationLogger
    }

    func deleteDeviceToken() {
        eventBusHandler.postEvent(DeleteDeviceTokenEvent())
    }

    func registerDeviceToken(_ deviceToken: String) {
        eventBusHandler.postEvent(RegisterDeviceTokenEvent(token: deviceToken))
    }

    func trackMetric(deliveryID: String, event: Metric, deviceToken: String) {
        eventBusHandler.postEvent(TrackMetricEvent(deliveryID: deliveryID, event: event.rawValue, deviceToken: deviceToken))
    }

    func trackMetricFromNSE(
        deliveryID: String,
        event: Metric,
        deviceToken: String
    ) {
        // Access richPushDeliveryTracker from DIGraphShared.shared directly as it is only required for NSE.
        // Keeping it as class property results in initialization of UserAgentUtil before SDK client is overridden by wrapper SDKs.
        // In future, we can improve how we access SdkClient so that we don't need to worry about initialization order.
        DIGraphShared.shared.richPushDeliveryTracker.trackMetric(token: deviceToken, event: event, deliveryId: deliveryID, timestamp: nil) { result in
            switch result {
            case .success:
                self.pushLogger.logPushMetricTracked(deliveryId: deliveryID, event: event.rawValue)
            case .failure(let error):
                self.pushLogger.logPushMetricTrackingFailed(deliveryId: deliveryID, event: event.rawValue, error: error)
            }
        }
    }

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
