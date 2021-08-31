import CioTracking
import Foundation

/**
 Swift code goes into this module that are common to *all* of the Messaging Push modules (APN, FCM, etc).
 So, performing an HTTP request to the API with a device token goes here.
  */
open class MessagingPush {
    
    public private(set) static var instance = MessagingPush(customerIO: CustomerIO.instance)

    private let customerIO: CustomerIO!
    private let httpClient: HttpClient

    private var credentials: SdkCredentials? {
        customerIO.credentials
    }

    private var sdkConfig: SdkConfig {
        customerIO.sdkConfig
    }
    
    public var deviceToken: Data?

    /// testing init
    internal init(customerIO: CustomerIO?, httpClient: HttpClient, keyValueStorage: KeyValueStorage) {
        self.customerIO = customerIO ?? CustomerIO(siteId: "fake", apiKey: "fake", region: Region.EU)
        self.httpClient = httpClient
    }

    /**
     Create a new instance of the `MessagingPush` class.

     - Parameters:
       - customerIO: Instance of `CustomerIO` class.
     */
    public init(customerIO: CustomerIO) {
        self.customerIO = customerIO
        self.httpClient = CIOHttpClient(credentials: customerIO.credentials!, config: customerIO.sdkConfig)
    }
    
    public func registerDeviceToken(deviceToken: Data, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        guard let bodyData = JsonAdapter.toJson(RegisterDeviceRequest(device: Device(token: deviceToken, lastUsed: Date()))) else {
            return onComplete(Result.failure(.httpError(.noResponse)))
        }
        
        if self.credentials == nil {
            return onComplete(Result.failure(.notInitialized))
        }
        
        guard let identifier = self.customerIO.identifier else {
            return onComplete(Result.failure(.notInitialized))
        }

        let httpRequestParameters = HttpRequestParams(endpoint: .registerDevice(identifier: identifier), headers: nil, body: bodyData)

        httpClient
            .request(httpRequestParameters) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success:
                    self.deviceToken = deviceToken
                    onComplete(Result.success(()))
                case .failure(let error):
                    onComplete(Result.failure(.httpError(error)))
                }
            }
    }
    
    public func deleteDeviceToken(onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        guard let bodyData = JsonAdapter.toJson(DeleteDeviceRequest()) else {
            return onComplete(Result.failure(.httpError(.noResponse)))
        }
        
        guard let deviceToken = self.deviceToken else {
            return onComplete(Result.failure(.notInitialized))
        }
        
        guard let identifier = self.customerIO.identifier else {
            return onComplete(Result.failure(.notInitialized))
        }

        let httpRequestParameters = HttpRequestParams(endpoint: .deleteDevice(identifier: identifier, deviceToken: deviceToken), headers: nil, body: bodyData)

        httpClient
            .request(httpRequestParameters) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success:
                    self.deviceToken = nil
                    onComplete(Result.success(()))
                case .failure(let error):
                    onComplete(Result.failure(.httpError(error)))
                }
            }
    }

}
