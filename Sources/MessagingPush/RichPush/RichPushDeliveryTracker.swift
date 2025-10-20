import CioInternalCommon
import Foundation

protocol RichPushDeliveryTracker: AutoMockable {
//    func trackMetric(token: String, event: Metric, deliveryId: String, timestamp: String?, onComplete: @escaping (Result<Void, HttpRequestError>) -> Void)

    func trackMetric(token: String, event: Metric, deliveryId: String, timestamp: String?) async -> Result<Void, HttpRequestError>
}

// sourcery: InjectRegisterShared = "RichPushDeliveryTracker"
class RichPushDeliveryTrackerImpl: RichPushDeliveryTracker {
    let httpClient: HttpClient
    let logger: Logger
    let region: Region

    init(httpClient: HttpClient, logger: Logger) {
        self.httpClient = httpClient
        self.logger = logger
        self.region = MessagingPush.moduleConfig.region
    }

    func trackMetric(token: String, event: Metric, deliveryId: String, timestamp: String? = nil) async -> Result<Void, HttpRequestError> {
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
            baseUrl: RichPushHttpClient.getDefaultApiHost(region: region),
            headers: nil,
            body: try? JSONSerialization.data(withJSONObject: properties)
        ) else {
            logger.error("Error constructing HTTP request. Endpoint: \(endpoint)")
//            return onComplete(.failure(.noRequestMade(nil)))
            return .failure(.noRequestMade(nil))
        }

        let result = await httpClient.request(httpParams)
        switch result {
        case .success: return .success(())
        case .failure(let httpError): return .failure(httpError)
        }

//        httpClient.request(httpParams) { result in
//            switch result {
//            case .success: onComplete(.success(()))
//            case .failure(let httpError): onComplete(.failure(httpError))
//            }
//        }
    }
}
