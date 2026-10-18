import CioInternalCommon
import Foundation
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
    func logPushMetricTracked(deliveryId: String, event: String)
    func logPushMetricTrackingFailed(deliveryId: String, event: String, error: Error)

    func logClickedPushMessage(notification: PushNotification)
    func logClickedCioPushMessage(deliveryId: String)
    func logClickedNonCioPushMessage()
    func logClickedPushMessageWithEmptyDeliveryId()
    func logTrackingPushMessageOpened(deliveryId: String)
}

// sourcery: InjectRegisterShared = "PushNotificationLogger"
class PushNotificationLoggerImpl: PushNotificationLogger {
    private static let PUSH_TAG = "Push"
    /// `in=` on `push.delivered`: whether this process is an app extension (the NSE) or the app.
    private static let process = processKind(bundlePath: Bundle.main.bundlePath)

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
        let tail = LogTail.make("push.delivered", ["id": LogTail.orNone(deliveryId), "in": Self.process])
        logger.debug("Tracking push message delivered with deliveryId: \(deliveryId)" + tail, Self.PUSH_TAG)
    }

    public func logPushMetricsAutoTrackingDisabled() {
        logger.debug("Received message but auto tracking is disabled", Self.PUSH_TAG)
    }

    public func logPushMetricTracked(deliveryId: String, event: String) {
        logger.debug("Successfully tracked push metric '\(event)' for deliveryId: \(deliveryId)", Self.PUSH_TAG)
    }

    public func logPushMetricTrackingFailed(deliveryId: String, event: String, error: Error) {
        logger.error("Failed to track push metric '\(event)' for deliveryId: \(deliveryId)", Self.PUSH_TAG, error)
    }

    // MARK: Click handling

    public func logClickedPushMessage(notification: PushNotification) {
        logger.debug("Clicked notification for message: \(notification)", Self.PUSH_TAG)
    }

    public func logClickedCioPushMessage(deliveryId: String) {
        let tail = LogTail.make("push.clicked", ["cio": "true", "id": LogTail.orNone(deliveryId)])
        logger.debug("Clicked CIO push message" + tail, Self.PUSH_TAG)
    }

    public func logClickedNonCioPushMessage() {
        let tail = LogTail.make("push.clicked", ["cio": "false"])
        logger.debug("Clicked non CIO push message, ignoring message" + tail, Self.PUSH_TAG)
    }

    public func logClickedPushMessageWithEmptyDeliveryId() {
        let tail = LogTail.make("push.clicked", ["cio": "true", "id": LogTail.none])
        logger.debug("Clicked message with empty deliveryId" + tail, Self.PUSH_TAG)
    }

    public func logTrackingPushMessageOpened(deliveryId: String) {
        let tail = LogTail.make("push.opened", ["id": LogTail.orNone(deliveryId)])
        logger.debug("Tracking push message opened with deliveryId: \(deliveryId)" + tail, Self.PUSH_TAG)
    }

    /// An app extension's bundle is an `.appex`.
    static func processKind(bundlePath: String) -> String {
        bundlePath.hasSuffix(".appex") ? "extension" : "app"
    }
}
