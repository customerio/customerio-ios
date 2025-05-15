import CioInternalCommon
#if canImport(UserNotifications) && canImport(UIKit)
import UserNotifications
#endif

protocol PushNotificationLogger: AutoMockable {
    func logReceivedPushMessage(notification: PushNotification)
    func logReceivedCioPushMessage()
    func logReceivedNonCioPushMessage()
    func logReceivedPushMessageWithEmptyDeliveryId()
    func logTrackingPushMessageDelivered(deliveryId: String)
    func logPushMetricsAutoTrackingDisabled()

    func logClickedPushMessage(notification: PushNotification)
    func logClickedCioPushMessage()
    func logClickedNonCioPushMessage()
    func logClickedPushMessageWithEmptyDeliveryId()
    func logTrackingPushMessageOpened(deliveryId: String)
}

// sourcery: InjectRegisterShared = "PushNotificationLogger"
class PushNotificationLoggerImpl: PushNotificationLogger {
    private static let PUSH_TAG = "Push"

    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    // MARK: Delivery handling

    public func logReceivedPushMessage(notification: PushNotification) {
        logger.debug("Received notification for message: \(notification)", Self.PUSH_TAG)
    }

    public func logReceivedCioPushMessage() {
        logger.debug("Received CIO push message", Self.PUSH_TAG)
    }

    public func logReceivedNonCioPushMessage() {
        logger.debug("Received non CIO push message, ignoring message", Self.PUSH_TAG)
    }

    public func logReceivedPushMessageWithEmptyDeliveryId() {
        logger.debug("Received message with empty deliveryId", Self.PUSH_TAG)
    }

    public func logTrackingPushMessageDelivered(deliveryId: String) {
        logger.debug("Tracking push message delivered with deliveryId: \(deliveryId)", Self.PUSH_TAG)
    }

    public func logPushMetricsAutoTrackingDisabled() {
        logger.debug("Received message but auto tracking is disabled", Self.PUSH_TAG)
    }

    // MARK: Click handling

    public func logClickedPushMessage(notification: PushNotification) {
        logger.debug("Clicked notification for message: \(notification)", Self.PUSH_TAG)
    }

    public func logClickedCioPushMessage() {
        logger.debug("Clicked CIO push message", Self.PUSH_TAG)
    }

    public func logClickedNonCioPushMessage() {
        logger.debug("Clicked non CIO push message, ignoring message", Self.PUSH_TAG)
    }

    public func logClickedPushMessageWithEmptyDeliveryId() {
        logger.debug("Clicked message with empty deliveryId", Self.PUSH_TAG)
    }

    public func logTrackingPushMessageOpened(deliveryId: String) {
        logger.debug("Tracking push message opened with deliveryId: \(deliveryId)", Self.PUSH_TAG)
    }
}
