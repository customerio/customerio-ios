import CioTracking
import Foundation

internal class MessagingPushImplementation: MessagingPushInstance {
    private let httpClient: HttpClient
    private let jsonAdapter: JsonAdapter
    private let eventBus: EventBus
    private let profileStore: ProfileStore
    private let backgroundQueue: Queue
    private var globalDataStore: GlobalDataStore

    private var identifyCustomerEventBusCallback: NSObjectProtocol?

    /// testing init
    internal init(
        httpClient: HttpClient,
        jsonAdapter: JsonAdapter,
        eventBus: EventBus,
        profileStore: ProfileStore,
        backgroundQueue: Queue,
        globalDataStore: GlobalDataStore
    ) {
        self.httpClient = httpClient
        self.jsonAdapter = jsonAdapter
        self.eventBus = eventBus
        self.profileStore = profileStore
        self.backgroundQueue = backgroundQueue
        self.globalDataStore = globalDataStore
    }

    init(siteId: String) {
        let diGraph = DITracking.getInstance(siteId: siteId)

        self.httpClient = diGraph.httpClient
        self.jsonAdapter = diGraph.jsonAdapter
        self.eventBus = diGraph.eventBus
        self.profileStore = diGraph.profileStore
        self.backgroundQueue = diGraph.queue
        self.globalDataStore = diGraph.globalDataStore

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
    public func registerDeviceToken(_ deviceToken: String) {
        // save push device token
        globalDataStore.pushDeviceToken = deviceToken

        guard let identifier = profileStore.identifier else {
            return
        }

        _ = backgroundQueue.addTask(type: QueueTaskType.registerPushToken.rawValue,
                                    data: RegisterPushNotificationQueueTaskData(profileIdentifier: identifier,
                                                                                deviceToken: deviceToken,
                                                                                lastUsed: Date()))
    }

    /**
     Delete the currently registered device token
     */
    public func deleteDeviceToken() {
        let existingDeviceToken = globalDataStore.pushDeviceToken
        globalDataStore.pushDeviceToken = nil

        guard let existingDeviceToken = existingDeviceToken, let identifiedProfileId = profileStore.identifier else {
            return // ignore request, no token to delete
        }

        _ = backgroundQueue.addTask(type: QueueTaskType.deletePushToken.rawValue,
                                    data: DeletePushNotificationQueueTaskData(profileIdentifier: identifiedProfileId,
                                                                              deviceToken: existingDeviceToken))
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
