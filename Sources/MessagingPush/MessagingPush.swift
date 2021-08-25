import Common
import Foundation

/**
 Swift code goes into this module that are common to *all* of the Messaging Push modules (APN, FCM, etc).
 So, performing an HTTP request to the API with a device token goes here.
  */
public class MessagingPush {
    
    public private(set) static var instance = MessagingPush(customerIO: CustomerIO.instance)

    private let customerIO: CustomerIO!
    private let httpClient: HttpClient

    private var credentials: SdkCredentials? {
        customerIO.credentials
    }

    private var sdkConfig: SdkConfig {
        customerIO.sdkConfig
    }

    /// testing init
    internal init(customerIO: CustomerIO?) {
        self.customerIO = customerIO ?? CustomerIO(siteId: "fake", apiKey: "fake", region: Region.EU)
    }

    /**
     Create a new instance of the `MessagingPush` class.

     - Parameters:
       - customerIO: Instance of `CustomerIO` class.
     */
    public init(customerIO: CustomerIO) {
        self.customerIO = customerIO
        
        self.httpClient = CIOHttpClient(credentials: credentials!, config: sdkConfig)
    }
    
    private func registerDeviceToken(token: String, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        guard let bodyData = JsonAdapter.toJson(RegisterDeviceRequest(device: Device(id: token, lastUsed: Date()))) else {
            return onComplete(Result.failure(.httpError(.noResponse)))
        }
        
        guard let identifier: String? = "fixme" else {
            return onComplete(Result.failure(.notInitialized))
        }

        let httpRequestParameters = HttpRequestParams(endpoint: .registerDevice(identifier: identifier!), headers: nil, body: bodyData)

        httpClient
            .request(httpRequestParameters) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success:
                    // XXX: store device token?
                    onComplete(Result.success(()))
                case .failure(let error):
                    onComplete(Result.failure(.httpError(error)))
                }
            }
    }
    
    private func deleteDeviceToken(onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        guard let bodyData = JsonAdapter.toJson(DeleteDeviceRequest()) else {
            return onComplete(Result.failure(.httpError(.noResponse)))
        }
        
        guard let token: String? = "fixme" else {
            return onComplete(Result.failure(.notInitialized))
        }
        
        guard let identifier: String? = "fixme" else {
            return onComplete(Result.failure(.notInitialized))
        }

        let httpRequestParameters = HttpRequestParams(endpoint: .deleteDevice(identifier: identifier!, token: token!), headers: nil, body: bodyData)

        httpClient
            .request(httpRequestParameters) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success:
                    // XXX: clear device token
                    onComplete(Result.success(()))
                case .failure(let error):
                    onComplete(Result.failure(.httpError(error)))
                }
            }
    }

}
