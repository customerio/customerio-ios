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
    private let jsonAdapter: JsonAdapter

    private var credentials: SdkCredentials? {
        customerIO.credentials
    }

    private var sdkConfig: SdkConfig {
        customerIO.sdkConfig
    }
    
    @Atomic public var deviceToken: Data?


    /// testing init
    internal init(customerIO: CustomerIO?, httpClient: HttpClient, keyValueStorage: KeyValueStorage, jsonAdapter: JsonAdapter) {
        self.customerIO = customerIO ?? CustomerIO(siteId: "fake", apiKey: "fake", region: Region.EU)
        self.httpClient = httpClient
        self.jsonAdapter = jsonAdapter
    }

    /**
     Create a new instance of the `MessagingPush` class.

     - Parameters:
       - customerIO: Instance of `CustomerIO` class.
     */
    public init(customerIO: CustomerIO) {
        self.customerIO = customerIO
        self.httpClient = CIOHttpClient(credentials: customerIO.credentials!, config: customerIO.sdkConfig)
        self.jsonAdapter = DITracking.shared.jsonAdapter
    }
    
    deinit{
        // XXX: handle deinit case where we want to delete the token
    }
 
    /**
     Register a new device token with Customer.io, associated with the current active customer. If there
     is no active customer, this will fail to register the device
     */
    public func registerDeviceToken(_ deviceToken: Data, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        let device = Device(token: String(decoding: deviceToken, as: UTF8.self), lastUsed: Date())
        guard let bodyData = jsonAdapter.toJson(RegisterDeviceRequest(device: device)) else {
            return onComplete(.failure(.http(.noRequestMade(nil))))
        }
        
        if self.credentials == nil {
            return onComplete(Result.failure(.notInitialized))
        }
        
        guard let identifier = self.customerIO.identifier else {
            return onComplete(Result.failure(.noCustomerIdentified))
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
                    onComplete(Result.failure(.http(error)))
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
        
        guard let identifier = self.customerIO.identifier else {
            // no customer identified, we can safely clear the device token
            self.deviceToken = nil
            return onComplete(Result.success(()))
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
                    onComplete(Result.failure(.http(error)))
                }
            }
    }

}
