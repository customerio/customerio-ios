import Common
import Foundation

public protocol CustomerIOInstance: AutoMockable {
    var siteId: String? { get }

    func identify(
        identifier: String,
        body: [String: Any]
    )

    // sourcery:Name=identifyEncodable
    // sourcery:DuplicateMethod=identify
    func identify<RequestBody: Encodable>(
        identifier: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(body)"
        body: RequestBody
    )

    func clearIdentify()

    func track(
        name: String,
        data: [String: Any]
    )

    // sourcery:Name=trackEncodable
    // sourcery:DuplicateMethod=track
    func track<RequestBody: Encodable>(
        name: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(data)"
        data: RequestBody?
    )

    func screen(
        name: String,
        data: [String: Any]
    )

    // sourcery:Name=screenEncodable
    // sourcery:DuplicateMethod=screen
    func screen<RequestBody: Encodable>(
        name: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(data)"
        data: RequestBody?
    )

    var profileAttributes: [String: Any] { get set }
    var deviceAttributes: [String: Any] { get set }

    // Any of the config functions not needed for mocking because config is designed to be called during application runtime during app startup.
    // Also, config() is not available for app extensions so we must make this function optional to inherit.
}

public extension CustomerIOInstance {
    func identify(
        identifier: String
    ) {
        identify(identifier: identifier, body: EmptyRequestBody())
    }

    func track(
        name: String
    ) {
        track(name: name, data: EmptyRequestBody())
    }

    func screen(
        name: String
    ) {
        screen(name: name, data: EmptyRequestBody())
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
        diGraph?.siteId
    }

    /**
     Singleton shared instance of `CustomerIO`. Convenient way to use the SDK.

     Note: Don't forget to call `CustomerIO.initialize()` before using this!
     */
    @Atomic public private(set) static var shared = CustomerIO()

    // Only assign a value to this *when the SDK is initialzied*.
    // It's assumed that if this instance is not-nil, the SDK has been initialized.
    // Tip: Use `SdkInitializedUtil` in modules to see if the SDK has been initialized and get data it needs.
    internal var implementation: CustomerIOImplementation?
    
    // The 1 place that DiGraph is strongly stored in memory for the SDK.
    // Exposed for `SdkInitializedUtil`. Not recommended to use this property directly.
    internal var diGraph: DIGraph?

    internal var globalData: GlobalDataStore = CioGlobalDataStore()
    // strong reference to repository to prevent garbage collection as it runs tasks in async.
    private var cleanupRepository: CleanupRepository?
//
//    private var threadUtil: ThreadUtil? {
//        guard let siteId = siteId else { return nil }
//
//        return DIGraph.getInstance(siteId: siteId).threadUtil
//    }
//
    private var logger: Logger? {
        guard let siteId = siteId else { return nil }

        return DIGraph.getInstance(siteId: siteId).logger
    }

    /**
     Constructor for singleton, only.

     Try loading the credentials previously saved for the singleton instance.
     */
    internal init() {
        if let siteId = globalData.sharedInstanceSiteId {
            let diGraph = DIGraph.getInstance(siteId: siteId)
            let credentialsStore = diGraph.sdkCredentialsStore
            let logger = diGraph.logger

            // if credentials are not available, we should not set implementation
            if credentialsStore.load() != nil {
                logger.info("shared instance of Customer.io loaded and ready to use")

                self.implementation = CustomerIOImplementation(siteId: siteId)
            } else {
                logger.info("shared instance of Customer.io needs to be initialized before ready to use")
            }
        }
    }
    
    // Constructor for unit testing. Just for overriding dependencies and not running logic.
    // See CustomerIO.shared.initializeIntegrationTests for integration testing
    internal init(implementation: CustomerIOImplementation, diGraph: DIGraph) {
        self.implementation = implementation
        self.diGraph = diGraph
    }

    /**
     Make testing the singleton `instance` possible.
     Note: It's recommended to delete app data before doing this to prevent loading persisted credentials
     */
    internal static func resetSharedInstance() {
        Self.shared = CustomerIO()
    }

    // Special initialize used for integration tests. Mostly to be able to shared a DI graph
    // between the SDK classes and test class. Runs all the same logic that the production `intialize` does.
    internal static func initializeIntegrationTests(
        siteId: String,
        diGraph: DIGraph
    ) {
        let implementation = CustomerIOImplementation(siteId: siteId)
        Self.shared = CustomerIO(implementation: implementation, diGraph: diGraph)

        Self.shared.postInitialize(siteId: diGraph.siteId)
    }
    
    /**
     Create an instance of `CustomerIO`.

     This is the recommended method for code bases containing
     automated tests, dependency injection, or sending data to multiple Workspaces.
     */
    @available(*, deprecated, message: "You must initialize Customer.io SDK using the shared instance")
    public init(siteId: String, apiKey: String, region: Region = Region.US) {
        setCredentials(siteId: siteId, apiKey: apiKey, region: region)

        self.implementation = CustomerIOImplementation(siteId: siteId)

        postInitialize(siteId: siteId)

        logger?.info("Customer.io SDK \(SdkVersion.version) initialized and ready to use for site id: \(siteId)")
    }

    public static func initialize(
        siteId: String,
        apiKey: String,
        region: Region = Region.US
    ) {
        Self.shared.globalData.sharedInstanceSiteId = siteId

        Self.shared.setCredentials(siteId: siteId, apiKey: apiKey, region: region)

        Self.shared.implementation = CustomerIOImplementation(siteId: siteId)

        Self.shared.postInitialize(siteId: siteId)

        Self.shared.logger?
            .info(
                "shared Customer.io SDK \(SdkVersion.version) instance initialized and ready to use for site id: \(siteId)"
            )
    }

    /**
     Initialize the shared `instance` of `CustomerIO`.
     Call this function when your app launches, before using `CustomerIO.instance`.
     */
    @available(iOSApplicationExtension, unavailable)
    public static func initialize(
        siteId: String,
        apiKey: String,
        region: Region = Region.US,
        configure configureHandler: ((inout SdkConfig) -> Void)?
    ) {
        Self.initialize(siteId: siteId, apiKey: apiKey, region: region)

        if let configureHandler = configureHandler {
            Self.config(configureHandler)
        }
    }

    /**
     Sets credentials on shared or non-shared instance.
     */
    internal func setCredentials(siteId: String, apiKey: String, region: Region) {
        let diGraph = DIGraph.getInstance(siteId: siteId)
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

        InMemoryActiveWorkspaces.getInstance().addWorkspace(siteId: siteId)
    }

    private func postInitialize(siteId: String) {
        let diGraph = DIGraph.getInstance(siteId: siteId)
        let threadUtil = diGraph.threadUtil
        
        // Register Tracking module hooks now that the module is being initialized.
        let hooksManager = diGraph.hooksManager
        hooksManager.add(key: .tracking, provider: TrackingModuleHookProvider(siteId: siteId))

        cleanupRepository = diGraph.cleanupRepository

        // run cleanup in background to prevent locking the UI thread
        threadUtil.runBackground { [weak self] in
            self?.cleanupRepository?.cleanup()
            self?.cleanupRepository = nil
        }
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
    @available(iOSApplicationExtension, unavailable)
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
    @available(iOSApplicationExtension, unavailable)
    public func config(_ handler: (inout SdkConfig) -> Void) {
        implementation?.config(handler)
    }

    /**
      Modify attributes to an already identified profile.

      Note: The getter of this field returns an empty dictionary. This is a setter only field.
     */
    public var profileAttributes: [String: Any] {
        get {
            implementation?.profileAttributes ?? [:]
        }
        set {
            implementation?.profileAttributes = newValue
        }
    }

    /**
     Use `deviceAttributes` to provide additional and custom device attributes
     apart from the ones the SDK is programmed to send to customer workspace.

     Example use:
     ```
     CustomerIO.shared.deviceAttributes = ["foo" : "bar"]
     ```
     */
    public var deviceAttributes: [String: Any] {
        get {
            implementation?.deviceAttributes ?? [:]
        }
        set {
            implementation?.deviceAttributes = newValue
        }
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
     */
    public func identify<RequestBody: Encodable>(
        identifier: String,
        body: RequestBody
    ) {
        // XXX: notify developer if SDK not initialized yet

        implementation?.identify(identifier: identifier, body: body)
    }

    public func identify(identifier: String, body: [String: Any]) {
        implementation?.identify(identifier: identifier, body: body)
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
     */
    public func track<RequestBody: Encodable>(
        name: String,
        data: RequestBody?
    ) {
        // XXX: notify developer if SDK not initialized yet

        implementation?.track(name: name, data: data)
    }

    public func track(name: String, data: [String: Any]) {
        implementation?.track(name: name, data: data)
    }

    public func screen(name: String, data: [String: Any]) {
        implementation?.screen(name: name, data: data)
    }

    /**
     Track a a screen view

     [Learn more](https://customer.io/docs/events/) about events in Customer.io

     - Parameters:
     - name: Name of the currently active screen
     - data: Optional event body data
     */
    public func screen<RequestBody: Encodable>(
        name: String,
        data: RequestBody
    ) {
        // XXX: notify developer if SDK not initialized yet

        implementation?.screen(name: name, data: data)
    }

    internal func automaticScreenView(
        name: String,
        data: [String: Any]
    ) {
        automaticScreenView(name: name, data: StringAnyEncodable(data))
    }

    // Designed to be called from swizzled methods for automatic screen tracking.
    // Because swizzled functions are not able to determine what siteId instance of
    // the SDK the app is using, we simply call `screen()` on all siteIds of the SDK
    // and if automatic screen view tracking is not setup for that siteId, the function
    // call to the instance will simply be ignored.
    internal func automaticScreenView<RequestBody: Encodable>(
        name: String,
        data: RequestBody
    ) {
        implementation?.screen(name: name, data: data)
    }
} // swiftlint:disable:this file_length
