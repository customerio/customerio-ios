import Foundation

public protocol CustomerIOInstance: AutoMockable {
    // MARK: - Profile

    /**
     Modify attributes to an already identified profile.
     Note: The getter of this field returns an empty dictionary. This is a setter only field.
     */
    @available(*, deprecated, message: "Use setProfileAttributes() instead")
    var profileAttributes: [String: Any] { get set }

    /**
     Set profile attributes for the currently identified customer.
     - Parameter attributes: Dictionary of attributes to set for the profile.
     */
    func setProfileAttributes(_ attributes: [String: Any])

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
    @available(*, deprecated, message: "Use 'identify(userId:traits:)' with [String: Any] traits parameter instead. Support for Codable traits will be removed in a future version.")
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
     @deprecated Use `setDeviceAttributes` method instead. This property getter always returns an empty dictionary.
     */
    @available(*, deprecated, message: "Use setDeviceAttributes method instead. This property getter always returns an empty dictionary.")
    var deviceAttributes: [String: Any] { get set }

    /**
     Set additional and custom device attributes apart from the ones the SDK is programmed to send to customer workspace.
     Example use:
     ```
     CustomerIO.shared.setDeviceAttributes(["foo": "bar"])
     ```
     - Parameters:
     - attributes: Dictionary of custom device attributes to set.
     */
    func setDeviceAttributes(_ attributes: [String: Any])

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
    @available(*, deprecated, message: "Use 'track(name:properties:)' with [String: Any] properties parameter instead. Support for Codable properties will be removed in a future version.")
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
    @available(*, deprecated, message: "Use 'screen(title:properties:)' with [String: Any] properties parameter instead. Support for Codable properties will be removed in a future version.")
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

    /// Bounded FIFO buffer that absorbs event-shaped public-API calls invoked
    /// before `implementation` is set. Drained synchronously, in order, by
    /// `initializeSharedInstance`/`setUpSharedInstanceForUnitTest` against the
    /// new implementation. After drain, subsequent calls bypass the buffer.
    let preInitEventBuffer = PreInitEventBuffer()

    /// Flag set when a `registerDeviceToken` call is buffered pre-init. Read by
    /// `postInitialize()` to skip its own stored-token registration so the
    /// buffered call (which carries the caller's most recent token) is the
    /// authoritative replay. Prevents the duplicate "Device Created or Updated"
    /// that would otherwise fire when both `postInitialize` and the buffered
    /// `registerDeviceToken` target the same stored token.
    private let hasPendingTokenRegistration = Synchronized<Bool>(false)

    /// private constructor to force use of singleton API
    private init() {}

    #if DEBUG
    // Methods to set up the test environment.
    // Any implementation of the interface works for unit tests.

    @discardableResult
    static func setUpSharedInstanceForUnitTest(implementation: CustomerIOInstance) -> CustomerIO {
        // Drain the buffer against the impl *before* publishing it on `shared`,
        // so concurrent `dispatch` calls can't bypass replay while pre-init
        // events are still queued.
        shared.preInitEventBuffer.transitionToReady(implementation)
        shared.implementation = implementation
        return shared
    }

    public static func resetSharedTestEnvironment() {
        shared = CustomerIO()
    }
    #endif

    public static func initializeSharedInstance(with implementation: CustomerIOInstance) {
        // Sync the stored device token first so buffered token-dependent calls
        // (e.g. `setDeviceAttributes`) observe a non-nil contextPlugin token
        // during replay. Then drain the buffer. Only after both have completed
        // do we publish `implementation`, so concurrent `dispatch` calls on
        // other threads either enqueue (and are picked up by the drain) or
        // execute directly post-drain — never racing past in-flight replay.
        shared.postInitialize(impl: implementation)
        shared.preInitEventBuffer.transitionToReady(implementation)
        shared.implementation = implementation
    }

    func postInitialize(impl: CustomerIOInstance) {
        // Register the device token during SDK initialization to address device registration issues
        // arising from lifecycle differences between wrapper SDKs and native SDK.
        //
        // If a `registerDeviceToken` call is already buffered, skip — the
        // buffered call carries the caller's most recent token and will run
        // during the drain. Registering here would either duplicate the
        // resulting Device Created or Updated event (same token) or cause an
        // unnecessary delete-and-re-register cycle (different token).
        guard !hasPendingTokenRegistration.wrappedValue else { return }
        let globalDataStore = diGraph.globalDataStore
        if let token = globalDataStore.pushDeviceToken {
            // Call directly on `impl` rather than via `self.dispatch`/
            // `registerDeviceToken`. `self.implementation` is intentionally
            // still `nil` at this point so the buffer remains the only path
            // for concurrent calls.
            impl.registerDeviceToken(token)
        }
    }

    // MARK: - CustomerIOInstance implementation

    /// Dispatch helper: when the SDK is initialized, calls the block against
    /// the real implementation immediately; otherwise enqueues it onto the
    /// pre-init buffer for replay once initialization completes.
    private func dispatch(_ block: @escaping (CustomerIOInstance) -> Void) {
        if let impl = implementation {
            block(impl)
        } else {
            preInitEventBuffer.enqueue(block)
        }
    }

    @available(*, deprecated, message: "Use setProfileAttributes() instead")
    public var profileAttributes: [String: Any] {
        get { implementation?.profileAttributes ?? [:] }
        set { setProfileAttributes(newValue) }
    }

    public func setProfileAttributes(_ attributes: [String: Any]) {
        dispatch { $0.setProfileAttributes(attributes) }
    }

    public func identify(userId: String, traits: [String: Any]? = nil) {
        dispatch { $0.identify(userId: userId, traits: traits) }
    }

    @available(*, deprecated, message: "Use 'identify(userId:traits:)' with [String: Any] traits parameter instead. Support for Codable traits will be removed in a future version.")
    public func identify<RequestBody: Codable>(userId: String, traits: RequestBody?) {
        dispatch { $0.identify(userId: userId, traits: traits) }
    }

    public func clearIdentify() {
        dispatch { $0.clearIdentify() }
    }

    public var deviceAttributes: [String: Any] {
        get { [:] }
        set { setDeviceAttributes(newValue) }
    }

    public func setDeviceAttributes(_ attributes: [String: Any]) {
        dispatch { $0.setDeviceAttributes(attributes) }
    }

    public var registeredDeviceToken: String? {
        implementation?.registeredDeviceToken
    }

    public func registerDeviceToken(_ deviceToken: String) {
        if let impl = implementation {
            impl.registerDeviceToken(deviceToken)
        } else {
            hasPendingTokenRegistration.wrappedValue = true
            preInitEventBuffer.enqueue { $0.registerDeviceToken(deviceToken) }
        }
    }

    public func deleteDeviceToken() {
        dispatch { $0.deleteDeviceToken() }
    }

    public func track(name: String, properties: [String: Any]? = nil) {
        dispatch { $0.track(name: name, properties: properties) }
    }

    @available(*, deprecated, message: "Use 'track(name:properties:)' with [String: Any] properties parameter instead. Support for Codable properties will be removed in a future version.")
    public func track<RequestBody: Codable>(name: String, properties: RequestBody?) {
        dispatch { $0.track(name: name, properties: properties) }
    }

    public func screen(title: String, properties: [String: Any]? = nil) {
        dispatch { $0.screen(title: title, properties: properties) }
    }

    @available(*, deprecated, message: "Use 'screen(title:properties:)' with [String: Any] properties parameter instead. Support for Codable properties will be removed in a future version.")
    public func screen<RequestBody: Codable>(title: String, properties: RequestBody?) {
        dispatch { $0.screen(title: title, properties: properties) }
    }

    public func trackMetric(deliveryID: String, event: Metric, deviceToken: String) {
        dispatch { $0.trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken) }
    }
}
