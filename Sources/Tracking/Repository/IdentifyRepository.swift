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
}

internal class CIOIdentifyRepository: IdentifyRepository {
    private let httpClient: HttpClient
    private let keyValueStorage: KeyValueStorage
    private let jsonAdapter: JsonAdapter
    private let siteId: String

    /// for testing
    internal init(httpClient: HttpClient, keyValueStorage: KeyValueStorage, jsonAdapter: JsonAdapter, siteId: String) {
        self.httpClient = httpClient
        self.keyValueStorage = keyValueStorage
        self.jsonAdapter = jsonAdapter
        self.siteId = siteId
    }

    init(credentials: SdkCredentials, config: SdkConfig) {
        self.httpClient = CIOHttpClient(credentials: credentials, config: config)
        self.siteId = credentials.siteId
        self.keyValueStorage = DITracking.shared.keyValueStorage
        self.jsonAdapter = DITracking.shared.jsonAdapter
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

                    onComplete(Result.success(()))
                case .failure(let error):
                    onComplete(Result.failure(.http(error)))
                }
            }
    }

    func removeCustomer() {
        keyValueStorage.setString(siteId: siteId, value: nil, forKey: .identifiedProfileId)
    }
}
