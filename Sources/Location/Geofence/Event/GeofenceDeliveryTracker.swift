import CioInternalCommon
import Foundation

/// Sends a single geofence transition event over direct HTTP to `/track`.
///
/// This is the primary delivery path in the three-layer design. Callers persist
/// the metric to `PendingGeofenceMetricStore` *before* calling `deliver`, then
/// remove it from the queue only after this returns success.
protocol GeofenceDeliveryTracker: AutoMockable {
    func deliver(
        metric: PendingGeofenceMetric,
        userId: String,
        onComplete: @escaping (Result<Void, HttpRequestError>) -> Void
    )
}

final class GeofenceDeliveryTrackerImpl: GeofenceDeliveryTracker {
    private let httpClient: HttpClient
    private let region: Region
    private let logger: Logger

    init(httpClient: HttpClient, region: Region, logger: Logger) {
        self.httpClient = httpClient
        self.region = region
        self.logger = logger
    }

    func deliver(
        metric: PendingGeofenceMetric,
        userId: String,
        onComplete: @escaping (Result<Void, HttpRequestError>) -> Void
    ) {
        guard !userId.isEmpty else {
            logger.error("cannot deliver geofence metric without a userId")
            return onComplete(.failure(.noRequestMade(nil)))
        }

        var properties: [String: Any] = [
            "geofence_id": metric.geofenceId,
            "transition_type": metric.transition.rawValue,
            "timestamp": Int(metric.timestamp.timeIntervalSince1970)
        ]
        if let latitude = metric.latitude { properties["latitude"] = latitude }
        if let longitude = metric.longitude { properties["longitude"] = longitude }

        let body: [String: Any] = [
            "event": metric.transition.trackEventName,
            "userId": userId,
            "properties": properties
        ]

        let endpoint: CIOApiEndpoint = .trackPushMetricsCdp
        guard let httpParams = HttpRequestParams(
            endpoint: endpoint,
            baseUrl: Self.apiHost(for: region),
            headers: nil,
            body: try? JSONSerialization.data(withJSONObject: body)
        ) else {
            logger.error("error constructing geofence delivery HTTP request")
            return onComplete(.failure(.noRequestMade(nil)))
        }

        httpClient.request(httpParams) { result in
            switch result {
            case .success:
                onComplete(.success(()))
            case .failure(let httpError):
                onComplete(.failure(httpError))
            }
        }
    }

    private static func apiHost(for region: Region) -> String {
        switch region {
        case .US: return "https://cdp.customer.io/v1"
        case .EU: return "https://cdp-eu.customer.io/v1"
        }
    }
}
