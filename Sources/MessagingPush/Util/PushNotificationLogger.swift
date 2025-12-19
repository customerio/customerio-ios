import CioInternalCommon
#if canImport(UserNotifications) && canImport(UIKit)
import UserNotifications
#endif

protocol PushNotificationLogger: Sendable, AutoMockable {
    func logReceivedPushMessage(notification: PushNotification)
    func logReceivedCioPushMessage()
    func logReceivedNonCioPushMessage()
    func logReceivedPushMessageWithEmptyDeliveryId()
    func logTrackingPushMessageDelivered(deliveryId: String)
    func logPushMetricsAutoTrackingDisabled()
    func logPushMetricTracked(deliveryId: String, event: String)
    func logPushMetricTrackingFailed(deliveryId: String, event: String, error: Error)

    func logClickedPushMessage(notification: PushNotification)
    func logClickedCioPushMessage()
    func logClickedNonCioPushMessage()
    func logClickedPushMessageWithEmptyDeliveryId()
    func logTrackingPushMessageOpened(deliveryId: String)
}

// sourcery: InjectRegisterShared = "PushNotificationLogger"
struct PushNotificationLoggerImpl: Sendable, PushNotificationLogger {

    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    // MARK: Delivery handling

    public func logReceivedPushMessage(notification: PushNotification) {
        logger.debug("Received notification for message: \(notification)", Tags.Push)
    }

    public func logReceivedCioPushMessage() {
        logger.debug("Received CIO push message", Tags.Push)
    }

    public func logReceivedNonCioPushMessage() {
        logger.debug("Received non CIO push message, ignoring message", Tags.Push)
    }

    public func logReceivedPushMessageWithEmptyDeliveryId() {
        logger.debug("Received message with empty deliveryId", Tags.Push)
    }

    public func logTrackingPushMessageDelivered(deliveryId: String) {
        logger.debug("Tracking push message delivered with deliveryId: \(deliveryId)", Tags.Push)
    }

    public func logPushMetricsAutoTrackingDisabled() {
        logger.debug("Received message but auto tracking is disabled", Tags.Push)
    }

    public func logPushMetricTracked(deliveryId: String, event: String) {
        logger.debug("Successfully tracked push metric '\(event)' for deliveryId: \(deliveryId)", Tags.Push)
    }

    public func logPushMetricTrackingFailed(deliveryId: String, event: String, error: Error) {
        logger.error("Failed to track push metric '\(event)' for deliveryId: \(deliveryId)", Tags.Push, error)
    }

    // MARK: Click handling

    public func logClickedPushMessage(notification: PushNotification) {
        logger.debug("Clicked notification for message: \(notification)", Tags.Push)
    }

    public func logClickedCioPushMessage() {
        logger.debug("Clicked CIO push message", Tags.Push)
    }

    public func logClickedNonCioPushMessage() {
        logger.debug("Clicked non CIO push message, ignoring message", Tags.Push)
    }

    public func logClickedPushMessageWithEmptyDeliveryId() {
        logger.debug("Clicked message with empty deliveryId", Tags.Push)
    }

    public func logTrackingPushMessageOpened(deliveryId: String) {
        logger.debug("Tracking push message opened with deliveryId: \(deliveryId)", Tags.Push)
    }
}
