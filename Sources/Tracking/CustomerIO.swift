import Foundation

public protocol CustomerIOInstance: AutoMockable {
    var siteId: String? { get }

    // sourcery:Name=identify
    func identify<RequestBody: Encodable>(
        identifier: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(body)"
        body: RequestBody,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void,
        jsonEncoder: JSONEncoder?
    )

    func clearIdentify()

    // sourcery:Name=track
    func track<RequestBody: Encodable>(
        name: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(data)"
        data: RequestBody?,
        jsonEncoder: JSONEncoder?,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    )

    // sourcery:Name=screenView
    func screen<RequestBody: Encodable>(
        name: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(data)"
        data: RequestBody?,
        jsonEncoder: JSONEncoder?,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    )

    func enableAutoScreenviewTracking()
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

    func track(
        name: String,
        jsonEncoder: JSONEncoder? = nil,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        track(name: name, data: EmptyRequestBody(), jsonEncoder: jsonEncoder, onComplete: onComplete)
    }

    func screen(
        name: String,
        jsonEncoder: JSONEncoder? = nil,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        screen(name: name, data: EmptyRequestBody(), jsonEncoder: jsonEncoder, onComplete: onComplete)
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
    public var siteId: String? {
        implementation?.siteId
    }

    /**
     Singleton shared instance of `CustomerIO`. Convenient way to use the SDK.

     Note: Don't forget to call `CustomerIO.initialize()` before using this!
     */
    @Atomic public private(set) static var shared = CustomerIO()

    internal var implementation: CustomerIOImplementation?

    internal var globalData: GlobalDataStore = CioGlobalDataStore()
    
    public var autoScreenViewBody: () -> ScreenViewData {
        get {
            self.implementation?.autoScreenViewBody ?? CustomerIOImplementation.defaultScreenViewBody
        }
        set {
            self.implementation?.autoScreenViewBody = newValue
        }
    }

    /**
     Constructor for singleton, only.

     Try loading the credentials previously saved for the singleton instance.
     */
    internal init() {
        if let siteId = globalData.sharedInstanceSiteId {
            let diGraph = DITracking.getInstance(siteId: siteId)
            let credentialsStore = diGraph.sdkCredentialsStore

            // if credentials are not available, we should not set implementation
            if credentialsStore.load() != nil {
                self.implementation = CustomerIOImplementation(siteId: siteId)
            }
        }
    }

    /**
     Make testing the singleton `instance` possible.
     Note: It's recommended to delete app data before doing this to prevent loading persisted credentials
     */
    internal static func resetSharedInstance() {
        Self.shared = CustomerIO()
    }

    /**
     Create an instance of `CustomerIO`.

     This is the recommended method for code bases containing
     automated tests, dependency injection, or sending data to multiple Workspaces.
     */
    public init(siteId: String, apiKey: String, region: Region = Region.US) {
        setCredentials(siteId: siteId, apiKey: apiKey, region: region)

        self.implementation = CustomerIOImplementation(siteId: siteId)
    }

    /**
     Initialize the shared `instance` of `CustomerIO`.
     Call this function when your app launches, before using `CustomerIO.instance`.
     */
    public static func initialize(siteId: String, apiKey: String, region: Region = Region.US) {
        Self.shared.globalData.sharedInstanceSiteId = siteId

        Self.shared.setCredentials(siteId: siteId, apiKey: apiKey, region: region)

        Self.shared.implementation = CustomerIOImplementation(siteId: siteId)
    }

    /**
     Sets credentials on shared or non-shared instance.
     */
    internal func setCredentials(siteId: String, apiKey: String, region: Region) {
        let diGraph = DITracking.getInstance(siteId: siteId)
        var credentialsStore = diGraph.sdkCredentialsStore

        credentialsStore.credentials = SdkCredentials(apiKey: apiKey, region: region)

        // Some default values of the SDK configuration may depend on credentials. Reset default values.
        var configStore = diGraph.sdkConfigStore
        var config = configStore.config

        if config.trackingApiUrl.isEmpty {
            config.trackingApiUrl = region.productionTrackingUrl
        }
        configStore.config = config

        globalData.appendSiteId(siteId)
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
        shared.config(handler)
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
        implementation?.config(handler)
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
        guard let implementation = self.implementation else {
            return onComplete(Result.failure(.notInitialized))
        }

        implementation.identify(identifier: identifier, body: body, onComplete: onComplete, jsonEncoder: jsonEncoder)
    }

    /**
     Stop identifying the currently persisted customer. All future calls to the SDK will no longer
     be associated with the previously identified customer.

     Note: If you simply want to identify a *new* customer, this function call is optional. Simply
     call `identify()` again to identify the new customer profile over the existing.

     If no profile has been identified yet, this function will ignore your request.
     */
    public func clearIdentify() {
        implementation?.clearIdentify()
    }

    /**
     Track an event

     [Learn more](https://customer.io/docs/events/) about events in Customer.io

     - Parameters:
     - name: Name of the event you want to track.
     - data: Optional event body data
     - onComplete: Asynchronous callback with `Result` of tracking an event.
     Check result to see if error or success. Callback called on main thread.
     - jsonEncoder: Provide custom JSONEncoder to have more control over the JSON request body
     */
    public func track<RequestBody: Encodable>(
        name: String,
        data: RequestBody,
        jsonEncoder: JSONEncoder? = nil,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        guard let implementation = self.implementation else {
            return onComplete(Result.failure(.notInitialized))
        }

        implementation.track(name: name, data: data, jsonEncoder: jsonEncoder, onComplete: onComplete)
    }

    /**
     Track a a screen view

     [Learn more](https://customer.io/docs/events/) about events in Customer.io

     - Parameters:
     - name: Name of the currently active screen. When automatically tracked, we use the name of the controller without any `ViewController` substrings
     - data: Optional event body data
     - onComplete: Asynchronous callback with `Result` of tracking an event.
     Check result to see if error or success. Callback called on main thread.
     - jsonEncoder: Provide custom JSONEncoder to have more control over the JSON request body
     */
    public func screen<RequestBody: Encodable>(
        name: String,
        data: RequestBody,
        jsonEncoder: JSONEncoder? = nil,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        guard let implementation = self.implementation else {
            return onComplete(Result.failure(.notInitialized))
        }

        implementation.screen(name: name, data: data, jsonEncoder: jsonEncoder, onComplete: onComplete)
    }

    public func enableAutoScreenviewTracking() {
        guard let implementation = self.implementation else {
            return
        }

        implementation.enableAutoScreenviewTracking()
    }
}
