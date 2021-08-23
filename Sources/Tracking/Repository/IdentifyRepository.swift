import Common
import Foundation

internal protocol IdentifyRepository: AutoMockable {
    func addOrUpdateCustomer(identifier: String,
                             email: String?,
                             onComplete: @escaping (Result<Void, Error>) -> Void)
}

internal class CIOIdentifyRepository: IdentifyRepository {
    private let httpClient: HttpClient
    private let keyValueStorage: KeyValueStorage
    private let siteId: String

    /// for testing
    internal init(httpClient: HttpClient, keyValueStorage: KeyValueStorage, siteId: String) {
        self.httpClient = httpClient
        self.keyValueStorage = keyValueStorage
        self.siteId = siteId
    }

    init(credentials: SdkCredentials, config: SdkConfig) {
        self.httpClient = CIOHttpClient(credentials: credentials, config: config)
        self.siteId = credentials.siteId
        self.keyValueStorage = DICommon.shared.keyValueStorage
    }

    func addOrUpdateCustomer(
        identifier: String,
        email: String?,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        let body = AddUpdateCustomerRequestBody(email: email, anonymousId: nil)

        /// because we control the object `body`, we don't anticipate a way for json encoding to fail
        // swiftlint:disable:next force_try
        let bodyData = try! JsonAdapter.toJson(body)

        let httpRequestParameters = HttpRequestParams(endpoint: .identifyCustomer(identifier: identifier), headers: nil,
                                                      body: bodyData)

        httpClient
            .request(httpRequestParameters) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success:
                    self.keyValueStorage.setString(siteId: self.siteId, value: identifier, forKey: .identifiedProfileId)
                    self.keyValueStorage.setString(siteId: self.siteId, value: email, forKey: .identifiedProfileEmail)

                    onComplete(Result.success(()))
                case .failure(let error):
                    onComplete(Result.failure(error))
                }
            }
    }
}
