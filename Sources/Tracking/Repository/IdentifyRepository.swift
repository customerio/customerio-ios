import Common
import Foundation

internal protocol IdentifyRepository: AutoMockable {
    func addOrUpdateCustomer(identifier: String,
                             email: String?,
                             createdAt: Date,
                             onComplete: @escaping (Result<Void, Error>) -> Void)
}

internal class CIOIdentifyRepository: IdentifyRepository {
    private let httpClient: HttpClient

    init(credentials: SdkCredentials, config: SdkConfig) {
        self.httpClient = CIOHttpClient(credentials: credentials, config: config)
    }

    func addOrUpdateCustomer(
        identifier: String,
        email: String?,
        createdAt: Date,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        let body = AddUpdateCustomerRequestBody(email: email, anonymousId: nil, createdAt: createdAt)

        guard let bodyData = try? JsonAdapter.toJson(body) else {
            return onComplete(Result
                .failure(HttpRequestError.failCreatingRequestBody(message: "Error creating request body: \(body)")))
        }

        httpClient.request(.identifyCustomer(identifier: identifier), headers: nil, body: bodyData) { result in
            switch result {
            case .success:
                onComplete(Result.success(()))
            case .failure(let error):
                onComplete(Result.failure(error))
            }
        }
    }
}
