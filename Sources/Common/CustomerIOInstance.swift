import Foundation

public protocol CustomerIOInstance: AutoMockable {
    // MARK: - Profile

    /**
     Modify attributes to an already identified profile.
     Note: The getter of this field returns an empty dictionary. This is a setter only field.
     */
    var profileAttributes: [String: Any] { get set }

    /**
     Identify a customer (aka: Add or update a profile).
     [Learn more](https://customer.io/docs/identifying-people/) about identifying a customer in Customer.io
     Note: You can only identify 1 profile at a time in your SDK. If you call this function multiple times,
     the previously identified profile will be removed. Only the latest identified customer is persisted.
     - Parameters:
     - userId: ID you want to assign to the customer.
     This value can be an internal ID that your system uses or an email address.
     [Learn more](https://customer.io/docs/api/#operation/identify)
     - traits: Dictionary traits of identifying profile. Use to define user attributes.
     */
    func identify(userId: String, traits: [String: Any]?)

    // swiftlint:disable orphaned_doc_comment
    /**
     Identify a customer (aka: Add or update a profile).
     [Learn more](https://customer.io/docs/identifying-people/) about identifying a customer in Customer.io
     Note: You can only identify 1 profile at a time in your SDK. If you call this function multiple times,
     the previously identified profile will be removed. Only the latest identified customer is persisted.
     - userId:
     - identifier: ID you want to assign to the customer.
     This value can be an internal ID that your system uses or an email address.
     [Learn more](https://customer.io/docs/api/#operation/identify)
     - traits: Request body of identifying profile. Use to define user attributes.
     */
    // swiftlint:enable orphaned_doc_comment
    // sourcery:Name=identifyEncodable
    // sourcery:DuplicateMethod=identify
    func identify<RequestBody: Codable>(
        userId: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(traits)"
        traits: RequestBody?
    )

    /**
     Stop identifying the currently persisted customer. All future calls to the SDK will no longer
     be associated with the previously identified customer.
     Note: If you simply want to identify a *new* customer, this function call is optional. Simply
     call `identify()` again to identify the new customer profile over the existing.
     If no profile has been identified yet, this function will ignore your request.
     */
    func clearIdentify()

    // MARK: - Device

    /**
     Use `deviceAttributes` to provide additional and custom device attributes
     apart from the ones the SDK is programmed to send to customer workspace.
     Example use:
     ```
     CustomerIO.shared.deviceAttributes = ["foo" : "bar"]
     ```
     */
    var deviceAttributes: [String: Any] { get set }

    /**
     Use `registeredDeviceToken` to fetch the current FCM/APN device token.
     This returns an optional string value.
     Example use:
     ```
     CustomerIO.shared.registeredDeviceToken
     ```
     */
    var registeredDeviceToken: String? { get }

    /**
     Register a new device token with Customer.io, associated with the current active customer. If there
     is no active customer, this will register the device to anonymous profile.
     */
    func registerDeviceToken(_ deviceToken: String)

    /**
     Delete the currently registered device token
     */
    func deleteDeviceToken()

    // MARK: - Events

    /**
     Track an event
     [Learn more](https://customer.io/docs/events/) about events in Customer.io
     - Parameters:
     - name: Name of the event you want to track.
     - properties: Optional dictionary of properties about the event.
     */
    func track(name: String, properties: [String: Any]?)

    // swiftlint:disable orphaned_doc_comment
    /**
     Track an event
     [Learn more](https://customer.io/docs/events/) about events in Customer.io
     - Parameters:
     - name: Name of the event you want to track.
     - properties: Optional event body of properties about the event.
     */
    // swiftlint:enable orphaned_doc_comment
    // sourcery:Name=trackEncodable
    // sourcery:DuplicateMethod=track
    func track<RequestBody: Codable>(
        name: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(properties)"
        properties: RequestBody?
    )

    // MARK: - Screen

    /**
     Track a screen view
     [Learn more](https://customer.io/docs/events/) about events in Customer.io
     - Parameters:
     - title: Name of the currently active screen
     - properties: Optional dictionary of properties about the screen.
     */
    func screen(title: String, properties: [String: Any]?)

    // swiftlint:disable orphaned_doc_comment
    /**
     Track a screen view
     [Learn more](https://customer.io/docs/events/) about events in Customer.io
     - Parameters:
     - title: Name of the currently active screen
     - properties: Optional event body of properties about the screen.
     */
    // swiftlint:enable orphaned_doc_comment
    // sourcery:Name=screenEncodable
    // sourcery:DuplicateMethod=screen
    func screen<RequestBody: Codable>(
        title: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(properties)"
        properties: RequestBody?
    )

    // MARK: - Custom Events

    /**
     Track a push metric
     */
    func trackMetric(deliveryID: String, event: Metric, deviceToken: String)
}

/**
 Welcome to the Customer.io iOS SDK!

 This class is where you begin to use the SDK.
 You must call `CustomerIO.initialize` to use the features of the SDK.
 */
public class CustomerIO: CustomerIOInstance {
    /// The current version of the Customer.io SDK.
    public static var version: String {
        SdkVersion.version
    }

    private var diGraph: DIGraphShared {
        DIGraphShared.shared
    }

    /**
     Singleton shared instance of `CustomerIO`. Convenient way to use the SDK.

     Note: Don't forget to call `CustomerIO.initialize()` before using this!
     */
    @Atomic public private(set) static var shared = CustomerIO()

    // Only assign a value to this *when the SDK is initialzied*.
    // It's assumed that if this instance is not-nil, the SDK has been initialized.
    // Tip: Use `SdkInitializedUtil` in modules to see if the SDK has been initialized and get data it needs.
    public var implementation: CustomerIOInstance?

    // private constructor to force use of singleton API
    private init() {}

    #if DEBUG
    // Methods to set up the test environment.
    // Any implementation of the interface works for unit tests.

    @discardableResult
    static func setUpSharedInstanceForUnitTest(implementation: CustomerIOInstance) -> CustomerIO {
        shared.implementation = implementation
        return shared
    }

    public static func resetSharedTestEnvironment() {
        shared = CustomerIO()
    }
    #endif

    public static func initializeSharedInstance(with implementation: CustomerIOInstance) {
        shared.implementation = implementation
        shared.postInitialize()
    }

    func postInitialize() {
        let logger = diGraph.logger

        // Register the device token during SDK initialization to address device registration issues
        // arising from lifecycle differences between wrapper SDKs and native SDK.
        let globalDataStore = diGraph.globalDataStore
        if let token = globalDataStore.pushDeviceToken {
            registerDeviceToken(token)
        }

        logger
            .info(
                "Customer.io SDK \(SdkVersion.version) initialized and ready to use"
            )
    }

    // MARK: - CustomerIOInstance implementation

    public var profileAttributes: [String: Any] {
        get { implementation?.profileAttributes ?? [:] }
        set { implementation?.profileAttributes = newValue }
    }

    public func identify(userId: String, traits: [String: Any]? = nil) {
        implementation?.identify(userId: userId, traits: traits)
    }

    public func identify<RequestBody: Codable>(userId: String, traits: RequestBody?) {
        implementation?.identify(userId: userId, traits: traits)
    }

    public func clearIdentify() {
        implementation?.clearIdentify()
    }

    public var deviceAttributes: [String: Any] {
        get { implementation?.deviceAttributes ?? [:] }
        set { implementation?.deviceAttributes = newValue }
    }

    public var registeredDeviceToken: String? {
        implementation?.registeredDeviceToken
    }

    public func registerDeviceToken(_ deviceToken: String) {
        implementation?.registerDeviceToken(deviceToken)
    }

    public func deleteDeviceToken() {
        implementation?.deleteDeviceToken()
    }

    public func track(name: String, properties: [String: Any]? = nil) {
        implementation?.track(name: name, properties: properties)
    }

    public func track<RequestBody: Codable>(name: String, properties: RequestBody?) {
        implementation?.track(name: name, properties: properties)
    }

    public func screen(title: String, properties: [String: Any]? = nil) {
        implementation?.screen(title: title, properties: properties)
    }

    public func screen<RequestBody: Codable>(title: String, properties: RequestBody?) {
        implementation?.screen(title: title, properties: properties)
    }

    public func trackMetric(deliveryID: String, event: Metric, deviceToken: String) {
        implementation?.trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken)
    }
}
