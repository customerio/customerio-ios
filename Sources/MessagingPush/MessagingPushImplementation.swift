import CioTracking
import Foundation

internal class MessagingPushImplementation: MessagingPushInstance {
    private let httpClient: HttpClient
    private let jsonAdapter: JsonAdapter
    private let pushDeviceTokenRepository: PushDeviceTokenRepository

    /// testing init
    internal init(
        httpClient: HttpClient,
        jsonAdapter: JsonAdapter,
        pushDeviceTokenRepository: PushDeviceTokenRepository
    ) {
        self.httpClient = httpClient
        self.jsonAdapter = jsonAdapter
        self.pushDeviceTokenRepository = pushDeviceTokenRepository
    }

    init(siteId: String) {
        let diGraph = DITracking.getInstance(siteId: siteId)
        let diGraphMessaging = DIMessagingPush.getInstance(siteId: siteId)

        self.httpClient = diGraph.httpClient
        self.jsonAdapter = diGraph.jsonAdapter
        self.pushDeviceTokenRepository = diGraphMessaging.pushDeviceTokenRepository
    }

    /**
     Register a new device token with Customer.io, associated with the current active customer. If there
     is no active customer, this will fail to register the device
     */
    public func registerDeviceToken(_ deviceToken: String) {
        pushDeviceTokenRepository.registerDeviceToken(deviceToken)
    }

    /**
     Delete the currently registered device token
     */
    public func deleteDeviceToken() {
        pushDeviceTokenRepository.deleteDeviceToken()
    }

    /**
     Track a push metric
     */
    public func trackMetric(
        deliveryID: String,
        event: Metric,
        deviceToken: String,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        let request = MetricRequest(deliveryID: deliveryID, event: event, deviceToken: deviceToken, timestamp: Date())

        guard let bodyData = jsonAdapter.toJson(request) else {
            return onComplete(.failure(.http(.noRequestMade(nil))))
        }

        let httpRequestParameters =
            HttpRequestParams(endpoint: .pushMetrics,
                              headers: nil, body: bodyData)

        httpClient
            .request(httpRequestParameters) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        onComplete(Result.success(()))
                    case .failure(let error):
                        onComplete(Result.failure(.http(error)))
                    }
                }
            }
    }
}
