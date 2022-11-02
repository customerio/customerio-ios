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

    // Any of the config functions not needed for mocking because config is designed to be called during application
    // runtime during app startup.
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
 You must call `CustomerIO.initialize` to use the features of the SDK.
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

    // Only assign a value to this *when the SDK is initialzied*.
    // It's assumed that if this instance is not-nil, the SDK has been initialized.
    internal var implementation: CustomerIOImplementation?

    public var diGraph: DIGraph? {
        implementation?.diGraph
    }

    // private constructor to force use of singleton API
    private init() {}

    // Constructor for testing.
    internal init(implementation: CustomerIOImplementation) {
        self.implementation = implementation
    }

    /**
     Make testing the singleton `instance` possible.
     Note: It's recommended to delete app data before doing this to prevent loading persisted credentials
     */
    internal static func resetSharedInstance() {
        Self.shared = CustomerIO()
    }

    /**
     Initialize the shared `instance` of `CustomerIO` from within a Notification Service Extension when setting up rich push.
     Call this function when your app launches, before using `CustomerIO.instance`.
     */
    @available(iOSApplicationExtension, introduced: 10)
    @available(iOS, unavailable)
    public static func initializeFromRichPush(
        siteId: String,
        apiKey: String,
        region: Region = Region.US,
        configure configureHandler: ((inout SdkConfig) -> Void)?
    ) {
        Self.initialize(
            siteId: siteId,
            apiKey: apiKey,
            region: region,
            configureHandler: configureHandler,
            fromRichPush: true
        )
    }

    /**
     Initialize the shared `instance` of `CustomerIO`.
     Call this function when your app launches, before using `CustomerIO.instance`.
     */
    @available(iOSApplicationExtension, unavailable)
    @available(iOS, introduced: 13)
    public static func initialize(
        siteId: String,
        apiKey: String,
        region: Region = Region.US,
        configure configureHandler: ((inout SdkConfig) -> Void)? = nil
    ) {
        Self.initialize(
            siteId: siteId,
            apiKey: apiKey,
            region: region,
            configureHandler: configureHandler,
            fromRichPush: false
        )
    }

    private static func initialize(
        siteId: String,
        apiKey: String,
        region: Region,
        configureHandler: ((inout SdkConfig) -> Void)?,
        fromRichPush: Bool
    ) {
        var newSdkConfig = SdkConfig.Factory.create(region: region)

        if let configureHandler = configureHandler {
            configureHandler(&newSdkConfig)
        }

        let newDiGraph = DIGraph(siteId: siteId, apiKey: apiKey, sdkConfig: newSdkConfig)

        Self.shared.implementation = CustomerIOImplementation(siteId: siteId, diGraph: newDiGraph)

        if newSdkConfig.autoTrackDeviceAttributes, !fromRichPush {
            Self.shared.implementation?.setupAutoScreenviewTracking()
        }

        Self.shared.implementation?.postInitialize()
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
