import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "RichPushDeliveryTracker"
class RichPushDeliveryTracker {
    let httpClient: HttpClient
    let logger: Logger

    init(httpClient: HttpClient, logger: Logger) {
        self.httpClient = httpClient
        self.logger = logger
    }

    func trackMetric(token: String, event: Metric, deliveryId: String, timestamp: String? = nil, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void) {
        let properties: [String: Any] = [
            "anonymousId": deliveryId,
            "properties": [
                "recipient": token,
                "metric": event.rawValue,
                "deliveryId": deliveryId
            ],
            "event": "Report Delivery Event"
        ]

        let endpoint: CIOApiEndpoint = .trackPushMetricsCdp
        guard let httpParams = HttpRequestParams(
            endpoint: endpoint,
            baseUrl: RichPushHttpClient.defaultAPIHost,
            headers: nil,
            body: try? JSONSerialization.data(withJSONObject: properties)
        ) else {
            logger.error("Error constructing HTTP request. Endpoint: \(endpoint)")
            return onComplete(.failure(.noRequestMade(nil)))
        }

        httpClient.request(httpParams) { result in
            switch result {
            case .success: onComplete(.success(()))
            case .failure(let httpError): onComplete(.failure(httpError))
            }
        }
    }
}
