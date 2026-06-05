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
    private let contextStore: BackgroundDeliveryContextStore
    private let logger: Logger

    init(httpClient: HttpClient, contextStore: BackgroundDeliveryContextStore, logger: Logger) {
        self.httpClient = httpClient
        self.contextStore = contextStore
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
        guard let apiHost = contextStore.currentApiHost, !apiHost.isEmpty else {
            logger.error("cannot deliver geofence metric without a persisted apiHost")
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
            baseUrl: Self.absoluteUrl(host: apiHost),
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

    /// `BackgroundDeliveryContextStore.currentApiHost` is host-only (no scheme); the request
    /// builder needs the full base URL, so prepend `https://` unless the caller has already
    /// qualified it.
    private static func absoluteUrl(host: String) -> String {
        if host.hasPrefix("http://") || host.hasPrefix("https://") {
            return host
        }
        return "https://" + host
    }
}
