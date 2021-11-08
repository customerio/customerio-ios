import Foundation

internal protocol IdentifyRepository: AutoMockable {
    func addOrUpdateCustomer(
        identifier: String,
        requestBodyString: String?,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    )

    func trackEvent(
        profileIdentifier: String,
        requestBodyString: String,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    )
}

// sourcery: InjectRegister = "IdentifyRepository"
internal class CIOIdentifyRepository: IdentifyRepository {
    private let httpClient: HttpClient
    private let jsonAdapter: JsonAdapter
    private let siteId: String

    init(
        siteId: SiteId,
        httpClient: HttpClient,
        jsonAdapter: JsonAdapter
    ) {
        self.siteId = siteId
        self.httpClient = httpClient
        self.jsonAdapter = jsonAdapter
    }

    func addOrUpdateCustomer(
        identifier: String,
        requestBodyString: String?,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        let httpRequestParameters = HttpRequestParams(endpoint: .identifyCustomer(identifier: identifier),
                                                      headers: nil,
                                                      body: requestBodyString?.data)

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

    func trackEvent(
        profileIdentifier: String,
        requestBodyString: String,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        let httpRequestParameters = HttpRequestParams(endpoint: .trackCustomerEvent(identifier: profileIdentifier),
                                                      headers: nil,
                                                      body: requestBodyString.data)

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
