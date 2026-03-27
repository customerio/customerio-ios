import CioInternalCommon
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

#if canImport(UserNotifications)

/// NSE delivery metric event sent to the Customer.io backend.
enum RichPushDeliveryEvent {
    case delivered
}

/// Bridges `UNNotificationRequest` to the existing delivery tracker for the NSE.
protocol RichPushDeliveryTracking: AnyObject {
    func trackMetric(
        request: UNNotificationRequest,
        event: RichPushDeliveryEvent,
        completion: @escaping (Result<Void, Error>) -> Void
    )
}

/// Default implementation: parses CIO delivery fields from the request and calls `RichPushDeliveryTracker`.
final class RichPushNSEDeliveryTracking: RichPushDeliveryTracking {
    private let tracker: RichPushDeliveryTracker
    private let pushLogger: PushNotificationLogger

    init(tracker: RichPushDeliveryTracker, pushLogger: PushNotificationLogger) {
        self.tracker = tracker
        self.pushLogger = pushLogger
    }

    func trackMetric(
        request: UNNotificationRequest,
        event: RichPushDeliveryEvent,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let push = UNNotificationWrapper(notificationRequest: request)
        guard let info = push.cioDelivery, event == .delivered else {
            completion(.failure(RichPushDeliveryTrackingError.missingCioDelivery))
            return
        }

        let deliveryId = info.id
        pushLogger.logTrackingPushMessageDelivered(deliveryId: deliveryId)
        tracker.trackMetric(
            token: info.token,
            event: .delivered,
            deliveryId: deliveryId,
            timestamp: nil
        ) { [weak self] result in
            switch result {
            case .success:
                self?.pushLogger.logPushMetricTracked(
                    deliveryId: deliveryId,
                    event: Metric.delivered.rawValue
                )
                completion(.success(()))
            case .failure(let error):
                self?.pushLogger.logPushMetricTrackingFailed(
                    deliveryId: deliveryId,
                    event: Metric.delivered.rawValue,
                    error: error
                )
                completion(.failure(error))
            }
        }
    }
}

enum RichPushDeliveryTrackingError: Error {
    case missingCioDelivery
}

#endif
