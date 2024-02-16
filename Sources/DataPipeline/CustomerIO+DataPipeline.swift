import CioInternalCommon
import Foundation

public protocol DataPipelinePublicAPI: AutoMockable {
    // MARK: - Profile

    var profileAttributes: [String: Any] { get set }
    func identify(userId: String, traits: [String: Any]?)
    // sourcery:Name=identifyEncodable
    // sourcery:DuplicateMethod=identify
    func identify<RequestBody: Codable>(
        userId: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(body)"
        traits: RequestBody?
    )
    func clearIdentify()

    // MARK: - Device

    var registeredDeviceToken: String? { get }
    var deviceAttributes: [String: Any] { get set }
    func registerDeviceToken(_ deviceToken: String)
    func deleteDeviceToken()

    // MARK: - Events

    func track(name: String, properties: [String: Any]?)
    // sourcery:Name=trackEncodable
    // sourcery:DuplicateMethod=track
    func track<RequestBody: Codable>(
        name: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(data)"
        properties: RequestBody?
    )

    // MARK: - Screen

    func screen(title: String, properties: [String: Any]?)
    // sourcery:Name=screenEncodable
    // sourcery:DuplicateMethod=screen
    func screen<RequestBody: Codable>(
        title: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(data)"
        properties: RequestBody?
    )

    // MARK: - Custom Events

    func trackMetric(deliveryID: String, event: Metric, deviceToken: String)
}

extension CustomerIO: DataPipelinePublicAPI {
    // MARK: - Profile

    /**
     Modify attributes to an already identified profile.
     Note: The getter of this field returns an empty dictionary. This is a setter only field.
     */
    public var profileAttributes: [String: Any] {
        get { DataPipeline.shared.profileAttributes }
        set { DataPipeline.shared.profileAttributes = newValue }
    }

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
    public func identify(userId: String, traits: [String: Any]? = nil) {
        DataPipeline.shared.identify(userId: userId, traits: traits)
    }

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
    // sourcery:Name=identifyEncodable
    // sourcery:DuplicateMethod=identify
    public func identify<RequestBody: Codable>(
        userId: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(body)"
        traits: RequestBody?
    ) {
        DataPipeline.shared.identify(userId: userId, traits: traits)
    }

    /**
     Stop identifying the currently persisted customer. All future calls to the SDK will no longer
     be associated with the previously identified customer.
     Note: If you simply want to identify a *new* customer, this function call is optional. Simply
     call `identify()` again to identify the new customer profile over the existing.
     If no profile has been identified yet, this function will ignore your request.
     */
    public func clearIdentify() {
        DataPipeline.shared.clearIdentify()
    }

    // MARK: - Device

    /**
     Use `registeredDeviceToken` to fetch the current FCM/APN device token.
     This returns an optional string value.
     Example use:
     ```
     CustomerIO.shared.registeredDeviceToken
     ```
     */
    public var registeredDeviceToken: String? {
        DataPipeline.shared.registeredDeviceToken
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
        get { DataPipeline.shared.deviceAttributes }
        set { DataPipeline.shared.deviceAttributes = newValue }
    }

    /**
     Register a new device token with Customer.io, associated with the current active customer. If there
     is no active customer, this will register the device to anonymous profile.
     */
    public func registerDeviceToken(_ deviceToken: String) {
        DataPipeline.shared.registerDeviceToken(deviceToken)
    }

    /**
     Delete the currently registered device token
     */
    public func deleteDeviceToken() {
        DataPipeline.shared.deleteDeviceToken()
    }

    // MARK: - Events

    /**
     Track an event
     [Learn more](https://customer.io/docs/events/) about events in Customer.io
     - Parameters:
     - name: Name of the event you want to track.
     - properties: Optional dictionary of properties about the event.
     */
    public func track(name: String, properties: [String: Any]? = nil) {
        DataPipeline.shared.track(name: name, properties: properties)
    }

    /**
     Track an event
     [Learn more](https://customer.io/docs/events/) about events in Customer.io
     - Parameters:
     - name: Name of the event you want to track.
     - properties: Optional event body of properties about the event.
     */
    // sourcery:Name=trackEncodable
    // sourcery:DuplicateMethod=track
    public func track<RequestBody: Codable>(
        name: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(data)"
        properties: RequestBody?
    ) {
        DataPipeline.shared.track(name: name, properties: properties)
    }

    // MARK: - Screen

    /**
     Track a screen view
     [Learn more](https://customer.io/docs/events/) about events in Customer.io
     - Parameters:
     - title: Name of the currently active screen
     - properties: Optional dictionary of properties about the screen.
     */
    public func screen(title: String, properties: [String: Any]? = nil) {
        DataPipeline.shared.screen(title: title, properties: properties)
    }

    /**
     Track a screen view
     [Learn more](https://customer.io/docs/events/) about events in Customer.io
     - Parameters:
     - title: Name of the currently active screen
     - properties: Optional event body of properties about the screen.
     */
    // sourcery:Name=screenEncodable
    // sourcery:DuplicateMethod=screen
    public func screen<RequestBody: Codable>(
        title: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(data)"
        properties: RequestBody?
    ) {
        DataPipeline.shared.screen(title: title, properties: properties)
    }

    // MARK: - Custom Events

    /**
     Track a push metric
     */
    public func trackMetric(deliveryID: String, event: Metric, deviceToken: String) {
        DataPipeline.shared.trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken)
    }
}
