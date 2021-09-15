import CioTracking
import Foundation

public protocol MessagingPushInstance: AutoMockable {
    func registerDeviceToken(_ deviceToken: Data, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void)
    func deleteDeviceToken(onComplete: @escaping (Result<Void, CustomerIOError>) -> Void)
}

/**
 Swift code goes into this module that are common to *all* of the Messaging Push modules (APN, FCM, etc).
 So, performing an HTTP request to the API with a device token goes here.
  */

public class MessagingPush: MessagingPushInstance {
    @Atomic public private(set) static var shared = MessagingPush(customerIO: CustomerIO.shared)

    public let customerIO: CustomerIO!
    private let httpClient: HttpClient
    private let jsonAdapter: JsonAdapter
    private let eventBus: EventBus

    private var identifyCustomerEventBusCallback: NSObjectProtocol?

    @Atomic public var deviceToken: Data?

    /// testing init
    internal init(customerIO: CustomerIO?, httpClient: HttpClient, jsonAdapter: JsonAdapter, eventBus: EventBus) {
        self.customerIO = customerIO ?? CustomerIO(siteId: "fake", apiKey: "fake", region: Region.EU)
        self.httpClient = httpClient
        self.jsonAdapter = jsonAdapter
        self.eventBus = eventBus
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
        self.eventBus = DITracking.shared.eventBus

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
    public func registerDeviceToken(_ deviceToken: Data,
                                    onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        let device = Device(token: String(apnDeviceToken: deviceToken), lastUsed: Date())
        guard let bodyData = jsonAdapter.toJson(RegisterDeviceRequest(device: device)) else {
            return onComplete(.failure(.http(.noRequestMade(nil))))
        }

        if customerIO.credentials == nil {
            return onComplete(Result.failure(.notInitialized))
        }

        guard let identifier = customerIO.identifier else {
            return onComplete(Result.failure(.noCustomerIdentified))
        }

        let httpRequestParameters = HttpRequestParams(endpoint: .registerDevice(identifier: identifier), headers: nil,
                                                      body: bodyData)

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

        guard let identifier = customerIO.identifier else {
            // no customer identified, we can safely clear the device token
            self.deviceToken = nil
            return onComplete(Result.success(()))
        }

        let httpRequestParameters =
            HttpRequestParams(endpoint: .deleteDevice(identifier: identifier, deviceToken: deviceToken),
                              headers: nil, body: bodyData)

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

// sourcery: InjectRegister = "DiPlaceholder"
internal class DiPlaceholder {}
