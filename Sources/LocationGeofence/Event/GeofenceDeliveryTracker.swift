import CioInternalCommon
import Foundation

/// Sends a single geofence transition event over direct HTTP to `/track`.
///
/// This is the primary delivery path in the three-layer design. Callers persist
/// the metric to `PendingGeofenceMetricStore` *before* calling `trackMetric`, then
/// remove it from the queue only after this returns success.
protocol GeofenceDeliveryTracker: AutoMockable {
    func trackMetric(
        metric: PendingGeofenceMetric,
        userId: String,
        onComplete: @escaping (Result<Void, BackgroundDeliveryHttpError>) -> Void
    )
}

final class GeofenceDeliveryTrackerImpl: GeofenceDeliveryTracker {
    private let httpClient: BackgroundDeliveryHttpClient
    private let logger: Logger

    init(httpClient: BackgroundDeliveryHttpClient, logger: Logger) {
        self.httpClient = httpClient
        self.logger = logger
    }

    func trackMetric(
        metric: PendingGeofenceMetric,
        userId: String,
        onComplete: @escaping (Result<Void, BackgroundDeliveryHttpError>) -> Void
    ) {
        guard !userId.isEmpty else {
            logger.error("cannot deliver geofence metric without a userId")
            return onComplete(.failure(.invalidRequest))
        }

        httpClient.sendTrackEvent(
            BackgroundTrackRequest(
                eventName: metric.trackEventName,
                userId: userId,
                properties: metric.trackEventProperties,
                timestamp: metric.timestamp
            ),
            completion: onComplete
        )
    }
}
