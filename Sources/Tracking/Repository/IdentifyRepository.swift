import Foundation

internal protocol IdentifyRepository: AutoMockable {
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

    func identifyLoggedOutCustomer(onComplete: @escaping (Result<Void, CustomerIOError>) -> Void)
    func clearLoggedOutCustomer()

    func mergeLoggedOutCustomer(
        mergeToIdentifier: String,
        jsonEncoder: JSONEncoder?,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    )
}

// sourcery: InjectRegister = "IdentifyRepository"
internal class CIOIdentifyRepository: IdentifyRepository {
    private let httpClient: HttpClient
    private let jsonAdapter: JsonAdapter
    private let eventBus: EventBus
    private let siteId: String
    private var profileStore: ProfileStore

    init(
        siteId: SiteId,
        httpClient: HttpClient,
        jsonAdapter: JsonAdapter,
        eventBus: EventBus,
        profileStore: ProfileStore
    ) {
        self.siteId = siteId
        self.httpClient = httpClient
        self.jsonAdapter = jsonAdapter
        self.eventBus = eventBus
        self.profileStore = profileStore
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
                    self.profileStore.identifier = identifier
                    self.eventBus.post(.identifiedCustomer)

                    onComplete(Result.success(()))
                case .failure(let error):
                    onComplete(Result.failure(.http(error)))
                }
            }
    }

    func removeCustomer() {
        profileStore.identifier = nil
    }

    func trackEvent<RequestBody: Encodable>(
        name: String,
        data: RequestBody?,
        timestamp: Date?,
        jsonEncoder: JSONEncoder?,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        guard let identifier = profileStore.identifier else {
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

    func identifyLoggedOutCustomer(onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        if profileStore.identifier != nil {
            return onComplete(Result.success(()))
        }

        // XXX: not quite sure that our String.random will be sufficient, need to double check
        let randomIdentifier = String.random

        let httpRequestParameters = HttpRequestParams(endpoint: .identifyCustomer(identifier: randomIdentifier),
                                                      headers: nil, body: nil)

        httpClient
            .request(httpRequestParameters) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success:
                    self.profileStore.loggedOutIdentifier = randomIdentifier
                    return onComplete(Result.success(()))
                case .failure(let error):
                    return onComplete(Result.failure(.http(error)))
                }
            }
    }

    func mergeLoggedOutCustomer(
        mergeToIdentifier: String,
        jsonEncoder: JSONEncoder?,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        guard let loggedOutIdentifier = profileStore.loggedOutIdentifier else {
            return
        }

        let mergeRequest = MergeCustomerRequestBody(primary: mergeToIdentifier, secondary: loggedOutIdentifier)

        guard let bodyData = jsonAdapter.toJson(mergeRequest, encoder: jsonEncoder) else {
            return onComplete(.failure(.http(.noRequestMade(nil))))
        }

        let httpRequestParameters = HttpRequestParams(endpoint: .mergeCustomers,
                                                      headers: nil, body: bodyData)

        httpClient
            .request(httpRequestParameters) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success:
                    self.profileStore.identifier = mergeToIdentifier
                    self.clearLoggedOutCustomer()
                    onComplete(Result.success(()))
                case .failure(let error):
                    onComplete(Result.failure(.http(error)))
                }
            }
    }

    func clearLoggedOutCustomer() {
        profileStore.clearLoggedOutIdentifier()
    }
}
