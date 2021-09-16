import Foundation

internal protocol IdentifyRepository: AutoMockable {
    var identifier: String? { get }

    func addOrUpdateCustomer<RequestBody: Encodable>(
        identifier: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(body)"
        body: RequestBody,
        jsonEncoder: JSONEncoder?,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    )
    func removeCustomer()

    func trackEvent<RequestBody: Encodable>(
        name: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(data)"
        data: RequestBody?,
        timestamp: Date?,
        jsonEncoder: JSONEncoder?,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    )

    func getIdentifier() -> String?
}

internal class CIOIdentifyRepository: IdentifyRepository {
    private let httpClient: HttpClient
    private let keyValueStorage: KeyValueStorage
    private let jsonAdapter: JsonAdapter
    private let eventBus: EventBus
    private let siteId: String

    public var identifier: String? {
        getIdentifier()
    }

    public func getIdentifier() -> String? {
        keyValueStorage.string(siteId: siteId, forKey: .identifiedProfileId)
    }

    /// for testing
    internal init(
        httpClient: HttpClient,
        keyValueStorage: KeyValueStorage,
        jsonAdapter: JsonAdapter,
        siteId: String,
        eventBus: EventBus
    ) {
        self.httpClient = httpClient
        self.keyValueStorage = keyValueStorage
        self.jsonAdapter = jsonAdapter
        self.siteId = siteId
        self.eventBus = eventBus
    }

    init(credentials: SdkCredentials, config: SdkConfig) {
        self.httpClient = CIOHttpClient(credentials: credentials, config: config)
        self.siteId = credentials.siteId
        self.keyValueStorage = DITracking.shared.keyValueStorage
        self.jsonAdapter = DITracking.shared.jsonAdapter
        self.eventBus = DITracking.shared.eventBus
    }

    func addOrUpdateCustomer<RequestBody: Encodable>(
        identifier: String,
        body: RequestBody,
        jsonEncoder: JSONEncoder?,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        guard let bodyData = jsonAdapter.toJson(body, encoder: jsonEncoder) else {
            return onComplete(.failure(.http(.noRequestMade(nil))))
        }

        let httpRequestParameters = HttpRequestParams(endpoint: .identifyCustomer(identifier: identifier), headers: nil,
                                                      body: bodyData)

        httpClient
            .request(httpRequestParameters) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success:
                    self.keyValueStorage.setString(siteId: self.siteId, value: identifier, forKey: .identifiedProfileId)
                    self.eventBus.post(.identifiedCustomer)

                    onComplete(Result.success(()))
                case .failure(let error):
                    onComplete(Result.failure(.http(error)))
                }
            }
    }

    func removeCustomer() {
        keyValueStorage.setString(siteId: siteId, value: nil, forKey: .identifiedProfileId)
    }

    func trackEvent<RequestBody: Encodable>(
        name: String,
        data: RequestBody?,
        timestamp: Date?,
        jsonEncoder: JSONEncoder?,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        guard let identifier = self.identifier else {
            // XXX: these could actually do one of
            // - fail
            // - send as anonymous events
            // - enqueue until a customer is identified
            // choosing to have them fail while we don't have a bg queue & while we discuss
            // plans for anonymous / pre-identify activity
            return onComplete(.failure(.noCustomerIdentified))
        }

        let trackRequest = TrackRequestBody(name: name, data: data, timestamp: timestamp)

        guard let bodyData = jsonAdapter.toJson(trackRequest, encoder: jsonEncoder) else {
            return onComplete(.failure(.http(.noRequestMade(nil))))
        }

        let httpRequestParameters = HttpRequestParams(endpoint: .trackCustomerEvent(identifier: identifier),
                                                      headers: nil,
                                                      body: bodyData)

        httpClient
            .request(httpRequestParameters) { result in
                switch result {
                case .success:
                    onComplete(Result.success(()))
                case .failure(let error):
                    onComplete(Result.failure(.http(error)))
                }
            }
    }
}
