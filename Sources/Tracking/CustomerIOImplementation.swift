import Foundation

/**
 Welcome to the Customer.io iOS SDK!

 This class is where you begin to use the SDK.
 You must have an instance of `CustomerIO` to use the features of the SDK.

 To get an instance, you have 2 options:
 1. Use the already provided singleton shared instance: `CustomerIO.instance`.
 This method is provided for convenience and is the easiest way to get started.

 2. Create your own instance: `CustomerIO(siteId: "XXX", apiKey: "XXX", region: Region.US)`
 This method is recommended for code bases containing
 automated tests, dependency injection, or sending data to multiple Workspaces.
 */
public class CustomerIOImplementation: CustomerIOInstance {
    public var siteId: String? {
        _siteId
    }

    private let profileStore: ProfileStore

    public var identifier: String? {
        profileStore.identifier
    }

    private let _siteId: String

    private let diGraph: DITracking

    private let identifyRepository: IdentifyRepository

    var autoScreenViewBody: (() -> [String: Any])?

    /**
     Constructor for singleton, only.

     Try loading the credentials previously saved for the singleton instance.
     */
    internal init(siteId: String) {
        self._siteId = siteId

        self.diGraph = DITracking.getInstance(siteId: siteId)

        self.identifyRepository = diGraph.identifyRepository

        self.profileStore = diGraph.profileStore
    }

    /**
     Configure the Customer.io SDK.

     This will configure the given non-singleton instance of CustomerIO.
     Cofiguration changes will only impact this 1 instance of the CustomerIO class.

     Example use:
     ```
     CustomerIO.config {
     $0.trackingApiUrl = "https://example.com"
     }
     ```
     */
    public func config(_ handler: (inout SdkConfig) -> Void) {
        var sdkConfigStore = diGraph.sdkConfigStore

        var configToModify = sdkConfigStore.config

        handler(&configToModify)

        sdkConfigStore.config = configToModify

        if sdkConfigStore.config.autoTrackScreenViews {
            setupAutoScreenviewTracking()
        }
    }

    public func identify<RequestBody: Encodable>(
        identifier: String,
        body: RequestBody,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void,
        jsonEncoder: JSONEncoder? = nil
    ) {
        identifyRepository
            .addOrUpdateCustomer(identifier: identifier, body: body, jsonEncoder: jsonEncoder) { [weak self] result in
                DispatchQueue.main.async { [weak self] in
                    guard self != nil else { return }

                    switch result {
                    case .success:
                        return onComplete(Result.success(()))
                    case .failure(let error):
                        return onComplete(Result.failure(error))
                    }
                }
            }
    }

    public func clearIdentify() {
        identifyRepository.removeCustomer()
    }

    public func track<RequestBody: Encodable>(
        name: String,
        data: RequestBody,
        jsonEncoder: JSONEncoder? = nil,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        // XXX: once we have a bg queue, if this gets deferred to later we should set a timestamp value
        identifyRepository
            .trackEvent(name: name, data: data, timestamp: nil, jsonEncoder: jsonEncoder) { [weak self] result in
                DispatchQueue.main.async { [weak self] in
                    guard self != nil else { return }

                    switch result {
                    case .success:
                        return onComplete(Result.success(()))
                    case .failure(let error):
                        return onComplete(Result.failure(error))
                    }
                }
            }
    }

    public func screen<RequestBody: Encodable>(
        name: String,
        data: RequestBody,
        jsonEncoder: JSONEncoder? = nil,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        // XXX: once we have a bg queue, if this gets deferred to later we should set a timestamp value
        identifyRepository
            .screen(name: name, data: data, timestamp: nil, jsonEncoder: jsonEncoder) { [weak self] result in
                DispatchQueue.main.async { [weak self] in
                    guard self != nil else { return }

                    switch result {
                    case .success:
                        return onComplete(Result.success(()))
                    case .failure(let error):
                        return onComplete(Result.failure(error))
                    }
                }
            }
    }
}
