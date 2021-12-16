import CioTracking
import Foundation

internal class MessagingPushImplementation: MessagingPushInstance {
    private let httpClient: HttpClient
    private let jsonAdapter: JsonAdapter
    private let eventBus: EventBus
    private let profileStore: ProfileStore

    private var identifyCustomerEventBusCallback: NSObjectProtocol?

    @Atomic public var deviceToken: String?

    /// testing init
    internal init(httpClient: HttpClient, jsonAdapter: JsonAdapter, eventBus: EventBus, profileStore: ProfileStore) {
        self.httpClient = httpClient
        self.jsonAdapter = jsonAdapter
        self.eventBus = eventBus
        self.profileStore = profileStore
    }

    init(siteId: String) {
        let diGraph = DI.getInstance(siteId: siteId)

        self.httpClient = diGraph.httpClient
        self.jsonAdapter = diGraph.jsonAdapter
        self.eventBus = diGraph.eventBus
        self.profileStore = diGraph.profileStore

        self.identifyCustomerEventBusCallback = eventBus.register(event: .identifiedCustomer) {
            //            if let deviceToken = self.deviceToken {
            // register device token with customer.
            //            }
        }
    }

    deinit {
        // XXX: handle deinit case where we want to delete the token

        self.eventBus.unregister(identifyCustomerEventBusCallback)
    }

    /**
     Register a new device token with Customer.io, associated with the current active customer. If there
     is no active customer, this will fail to register the device
     */
    public func registerDeviceToken(_ deviceToken: String,
                                    onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        let device = Device(token: deviceToken, lastUsed: Date())
        guard let bodyData = jsonAdapter.toJson(RegisterDeviceRequest(device: device)) else {
            return onComplete(.failure(.http(.noRequestMade(nil))))
        }

        guard let identifier = profileStore.identifier else {
            return onComplete(Result.failure(.noCustomerIdentified))
        }

        let httpRequestParameters = HttpRequestParams(endpoint: .registerDevice(identifier: identifier), headers: nil,
                                                      body: bodyData)

        httpClient
            .request(httpRequestParameters) { [weak self] result in
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }

                    switch result {
                    case .success:
                        self.deviceToken = deviceToken
                        onComplete(Result.success(()))
                    case .failure(let error):
                        onComplete(Result.failure(.http(error)))
                    }
                }
            }
    }

    /**
     Delete the currently registered device token
     */
    public func deleteDeviceToken(onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        guard let bodyData = jsonAdapter.toJson(DeleteDeviceRequest()) else {
            return onComplete(.failure(.http(.noRequestMade(nil))))
        }

        guard let deviceToken = self.deviceToken else {
            // no device token, delete has already happened or is not needed
            return onComplete(Result.success(()))
        }

        guard let identifier = profileStore.identifier else {
            // no customer identified, we can safely clear the device token
            self.deviceToken = nil
            return onComplete(Result.success(()))
        }

        let httpRequestParameters =
            HttpRequestParams(endpoint: .deleteDevice(identifier: identifier,
                                                      deviceToken: deviceToken),
                              headers: nil, body: bodyData)

        httpClient
            .request(httpRequestParameters) { [weak self] result in
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }

                    switch result {
                    case .success:
                        self.deviceToken = nil
                        onComplete(Result.success(()))
                    case .failure(let error):
                        onComplete(Result.failure(.http(error)))
                    }
                }
            }
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
