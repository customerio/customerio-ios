import Foundation
public protocol CustomerIOInstance: AutoMockable {
    var siteId: String? { get }

    /// Get the current configuration options set for the SDK.
    var config: SdkConfig? { get }

    func identify(
        identifier: String,
        body: [String: Any]
    )

    // sourcery:Name=identifyEncodable
    // sourcery:DuplicateMethod=identify
    func identify<RequestBody: Codable>(
        identifier: String,
        // TODO: update AnyEncodable to AnyCodable?
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(body)"
        body: RequestBody
    )

    // sourcery:Name=identifyAnonymousEncodable
    // sourcery:DuplicateMethod=identify
    func identify(body: Codable)

    var registeredDeviceToken: String? { get }

    func clearIdentify()

    func track(
        name: String,
        data: [String: Any]
    )

    // sourcery:Name=trackEncodable
    // sourcery:DuplicateMethod=track
    func track<RequestBody: Codable>(
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
    func screen<RequestBody: Codable>(
        name: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(data)"
        data: RequestBody?
    )

    var profileAttributes: [String: Any] { get set }
    var deviceAttributes: [String: Any] { get set }

    func registerDeviceToken(_ deviceToken: String)

    func deleteDeviceToken()

    func trackMetric(
        deliveryID: String,
        event: Metric,
        deviceToken: String
    )
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

    public var siteId: String? {
        diGraph?.sdkConfig.siteId
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

    // The 1 place that DiGraph is strongly stored in memory for the SDK.
    // Exposed for `SdkInitializedUtil`. Not recommended to use this property directly.
    public var diGraph: DIGraph?

    // private constructor to force use of singleton API
    private init() {}

    #if DEBUG
    // Constructor for unit testing. Just for overriding dependencies and not running logic.
    // See CustomerIO.initializeAndSetSharedTestInstance for integration testing
    init(implementation: CustomerIOInstance, diGraph: DIGraph) {
        self.implementation = implementation
        self.diGraph = diGraph
    }
    #endif

    public static func initializeSharedInstance(with implementation: CustomerIOInstance, diGraph: DIGraph) {
        shared.implementation = implementation
        shared.diGraph = diGraph
        shared.postInitialize(diGraph: diGraph)
    }

    func postInitialize(diGraph: DIGraph) {
        let logger = diGraph.logger
        let siteId = diGraph.sdkConfig.siteId

        // Register the device token during SDK initialization to address device registration issues
        // arising from lifecycle differences between wrapper SDKs and native SDK.
        let globalDataStore = diGraph.globalDataStore
        if let token = globalDataStore.pushDeviceToken {
            registerDeviceToken(token)
        }

        logger
            .info(
                "Customer.io SDK \(SdkVersion.version) initialized and ready to use for site id: \(siteId)"
            )
    }

    #if DEBUG
    /**
     Resets the shared `CustomerIO` instance to its initial state, only for testing purpose.
     */
    public static func resetSharedTestInstance() {
        shared = CustomerIO()
    }
    #endif

    /**
     Use `registeredDeviceToken` to fetch the current FCM/APN device token.
     This returns an optional string value.
     Example use:
     ```
     CustomerIO.shared.registeredDeviceToken
     ```
     */
    public var registeredDeviceToken: String? {
        implementation?.registeredDeviceToken
    }

    public var config: SdkConfig? {
        implementation?.config
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
    public func identify<RequestBody: Codable>(
        identifier: String,
        body: RequestBody
    ) {
        // This code handles a specific scenario where a user
        // unexpectedly provides a `nil` value for the RequestBody
        // parameter, which the method isn't designed to handle directly.
        // To prevent errors and ensure compatibility, this condition checks
        // if the `body` is `nil`. If it is, it substitutes it with an
        // EmptyRequestBody() object before passing it along to the
        // identify(). This replacement safeguards against possible
        // issues that could arise(eg. app crash). While the `identify`
        // method itself provide polymorphic capabilities to handle `nil`,
        // this specific check within this method offers an additional
        // layer of protection and clarity for this case.
        // (refer https://github.com/customerio/customerio-ios/blob/94cbf686c3c2a405534cfe908f7166558a3e0b5d/Sources/Tracking/CustomerIO.swift#L71-L75)
        if let optionalValue = body as? Any?, optionalValue == nil {
            implementation?.identify(identifier: identifier, body: EmptyRequestBody())
            return
        }
        implementation?.identify(identifier: identifier, body: body)
    }

    public func identify(body: Codable) {
        implementation?.identify(body: body)
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
    public func track<RequestBody: Codable>(
        name: String,
        data: RequestBody?
    ) {
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
    public func screen<RequestBody: Codable>(
        name: String,
        data: RequestBody
    ) {
        implementation?.screen(name: name, data: data)
    }

    func automaticScreenView(
        name: String,
        data: [String: Any]
    ) {
        guard (diGraph?.logger) != nil else {
            return
        }
        implementation?.screen(name: name, data: data)
    }

    /**
     Register a new device token with Customer.io, associated with the current active customer. If there
     is no active customer, this will fail to register the device
     */
    public func registerDeviceToken(_ deviceToken: String) {
        implementation?.registerDeviceToken(deviceToken)
    }

    /**
     Delete the currently registered device token
     */
    public func deleteDeviceToken() {
        implementation?.deleteDeviceToken()
    }

    /**
     Track a push metric
     */
    public func trackMetric(
        deliveryID: String,
        event: Metric,
        deviceToken: String
    ) {
        implementation?.trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken)
    }
} // swiftlint:disable:this file_length
