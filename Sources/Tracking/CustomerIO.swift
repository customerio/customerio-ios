import Foundation

public protocol CustomerIOInstance: AutoMockable {
    // sourcery:Name=identifyBody
    func identify<RequestBody: Encodable>(
        identifier: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(body)"
        body: RequestBody,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void,
        jsonEncoder: JSONEncoder?
    )
    func clearIdentify()
}

public extension CustomerIOInstance {
    /**
     Identify a customer (aka: Add or update a profile).

     [Learn more](https://customer.io/docs/identifying-people/) about identifying a customer in Customer.io

     Note: You can only identify 1 profile at a time in your SDK. If you call this function multiple times,
     the previously identified profile will be removed. Only the latest identified customer is persisted.

     - Parameters:
     - identifier: ID you want to assign to the customer.
     This value can be an internal ID that your system uses or an email address.
     [Learn more](https://customer.io/docs/api/#operation/identify)
     - onComplete: Asynchronous callback with `Result` of identifying a customer.
     Check result to see if error or success. Callback called on main thread.
     - jsonEncoder: Provide custom JSONEncoder to have more control over the JSON request body for attributes.
     */
    func identify(
        identifier: String,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void,
        jsonEncoder: JSONEncoder? = nil
    ) {
        identify(identifier: identifier, body: EmptyRequestBody(), onComplete: onComplete, jsonEncoder: jsonEncoder)
    }

    /**
     Identify a customer (aka: Add or update a profile).

     [Learn more](https://customer.io/docs/identifying-people/) about identifying a customer in Customer.io

     Note: You can only identify 1 profile at a time in your SDK. If you call this function multiple times,
     the previously identified profile will be removed. Only the latest identified customer is persisted.

     - Parameters:
     - identifier: ID you want to assign to the customer.
     This value can be an internal ID that your system uses or an email address.
     [Learn more](https://customer.io/docs/api/#operation/identify)
     - onComplete: Asynchronous callback with `Result` of identifying a customer.
     Check result to see if error or success. Callback called on main thread.
     - email: Optional email address you want to associate with a profile.
     If you use an email address as the `identifier` this is not needed.
     - jsonEncoder: Provide custom JSONEncoder to have more control over the JSON request body for attributes.
     */
    func identify<RequestBody: Encodable>(
        identifier: String,
        body: RequestBody,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void,
        jsonEncoder: JSONEncoder? = nil
    ) {
        identify(identifier: identifier, body: body, onComplete: onComplete, jsonEncoder: jsonEncoder)
    }
}

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
public class CustomerIO: CustomerIOInstance {
    /**
     Singleton shared instance of `CustomerIO`. Convenient way to use the SDK.

     Note: Don't forget to call `CustomerIO.initialize()` before using this!
     */
    @Atomic public private(set) static var instance = CustomerIO()

    @Atomic public var sdkConfig: SdkConfig
    @Atomic public var credentials: SdkCredentials?
    
    public var identifier: String? {
        return self.identifyRepository?.identifier
    }

    private var credentialsStore: SdkCredentialsStore = DITracking.shared.sdkCredentialsStore
    private var keyValueStorage: KeyValueStorage = DITracking.shared.keyValueStorage

    /**
     init for testing

     Note: Using real key/value storage can be handy in tests. make them optional
     */
    internal init(
        credentialsStore: SdkCredentialsStore?,
        sdkConfig: SdkConfig,
        identifyRepository: IdentifyRepository?,
        keyValueStorage: KeyValueStorage?
    ) {
        self._identifyRepository = identifyRepository
        if let keyValueStorage = keyValueStorage {
            self.keyValueStorage = keyValueStorage
        }
        if let credentialsStore = credentialsStore {
            self.credentialsStore = credentialsStore
        }
        self.sdkConfig = sdkConfig
    }

    /**
     Constructor for singleton, only.

     Try loading the credentials previously saved for the singleton instance.
     */
    internal init() {
        let newSdkConfig = SdkConfig()
        self.sdkConfig = newSdkConfig

        if let siteId = credentialsStore.sharedInstanceSiteId,
           let existingCredentials = credentialsStore.load(siteId: siteId) {
            self.credentials = existingCredentials
            self._identifyRepository = CIOIdentifyRepository(credentials: existingCredentials, config: newSdkConfig)
        }
    }

    /**
     Make testing the singleton `instance` possible.
     Note: It's recommended to delete app data before doing this to prevent loading persisted credentials
     */
    internal static func resetSharedInstance() {
        Self.instance = CustomerIO()
    }

    /**
     allow `_` character in property name. It's common to use a `_` in property name for private variables
     but a refactor in the future will remove the need for this property all together so, just disable
     the lint rule for now.
     */
    // swiftlint:disable identifier_name

    /**
     Keep a class wide reference to `IdentifyRepository` to keep it in memory as it performs async operations.
     */
    private var _identifyRepository: IdentifyRepository?
    /**
     Because the repository can be populated from tests and it depends on the SDK being initialized,
     there needs to exist logic to provide the `IdentifyRepository` instance to the class.

     If a backgroud queue would exist in the SDK, this code can go away where each function of the class
     simply adds a task to the queue and the queue will run or not run the operation depending on if
     the SDK has been initialized.
     */
    private var identifyRepository: IdentifyRepository? {
        if let _identifyRepository = self._identifyRepository { return _identifyRepository }

        guard let credentials = credentials else { return nil }

        _identifyRepository = CIOIdentifyRepository(credentials: credentials, config: sdkConfig)

        return _identifyRepository
    }

    // swiftlint:enable identifier_name

    /**
     Create an instance of `CustomerIO`.

     This is the recommended method for code bases containing
     automated tests, dependency injection, or sending data to multiple Workspaces.
     */
    public init(siteId: String, apiKey: String, region: Region = Region.US) {
        self.sdkConfig = Self.instance.sdkConfig

        setCredentials(siteId: siteId, apiKey: apiKey, region: region)
    }

    /**
     Initialize the shared `instance` of `CustomerIO`.
     Call this function when your app launches, before using `CustomerIO.instance`.
     */
    public static func initialize(siteId: String, apiKey: String, region: Region = Region.US) {
        Self.instance.setCredentials(siteId: siteId, apiKey: apiKey, region: region)

        Self.instance.credentialsStore.sharedInstanceSiteId = siteId
    }

    /**
     Sets credentials on shared or non-shared instance.
     */
    internal func setCredentials(siteId: String, apiKey: String, region: Region) {
        var credentials = credentialsStore.load(siteId: siteId)
            ?? credentialsStore.create(siteId: siteId, apiKey: apiKey, region: region)

        credentials = credentials.apiKeySet(apiKey).regionSet(region)

        self.credentials = credentials
        credentialsStore.save(siteId: siteId, credentials: credentials)

        // Some default values of the SDK configuration may depend on credentials. Reset default values.
        sdkConfig = setDefaultValuesSdkConfig(config: sdkConfig)

        _identifyRepository = CIOIdentifyRepository(credentials: credentials, config: sdkConfig)
    }

    /**
     Configure the Customer.io SDK.

     This will configure the singleton shared instance of the CustomerIO class. It will also be the default
     configuration for all future non-singleton instances of the CustomerIO class.

     Example use:
     ```
     CustomerIO.config {
       $0.trackingApiUrl = "https://example.com"
     }
     ```
     */
    public static func config(_ handler: (inout SdkConfig) -> Void) {
        instance.config(handler)
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
        var configToModify = sdkConfig

        handler(&configToModify)
        configToModify = setDefaultValuesSdkConfig(config: configToModify)

        sdkConfig = configToModify
    }

    internal func setDefaultValuesSdkConfig(config: SdkConfig) -> SdkConfig {
        var config = config

        if config.trackingApiUrl.isEmpty, let credentials = self.credentials {
            config.trackingApiUrl = credentials.region.productionTrackingUrl
        }

        return config
    }

    /**
     Identify a customer (aka: Add or update a profile).

     [Learn more](https://customer.io/docs/identifying-people/) about identifying a customer in Customer.io

     Note: You can only identify 1 profile at a time in your SDK. If you call this function multiple times,
     the previously identified profile will be removed. Only the latest identified customer is persisted.

     - Parameters:
     - identifier: ID you want to assign to the customer.
     This value can be an internal ID that your system uses or an email address.
     [Learn more](https://customer.io/docs/api/#operation/identify)
     - body: Request body of identifying profile. Use to define user attributes.
     - onComplete: Asynchronous callback with `Result` of identifying a customer.
     Check result to see if error or success. Callback called on main thread.
     - jsonEncoder: Provide custom JSONEncoder to have more control over the JSON request body for attributes.
     */
    public func identify<RequestBody: Encodable>(
        identifier: String,
        body: RequestBody,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void,
        jsonEncoder: JSONEncoder? = nil
    ) {
        guard let identifyRepository = self.identifyRepository else {
            return onComplete(Result.failure(.notInitialized))
        }

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

    /**
     Stop identifying the currently persisted customer. All future calls to the SDK will no longer
     be associated with the previously identified customer.

     Note: If you simply want to identify a *new* customer, this function call is optional. Simply
     call `identify()` again to identify the new customer profile over the existing.

     If no profile has been identified yet, this function will ignore your request.
     */
    public func clearIdentify() {
        guard let identifyRepository = self.identifyRepository else {
            return
        }

        identifyRepository.removeCustomer()
    }
}
