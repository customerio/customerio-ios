import CioInternalCommon
import Segment

public protocol DataPipelineInstance: CustomerIOInstance {
    var analytics: Analytics { get }
    func processIdentifyFromBGQ(identifier: String, timestamp: String, body: [String: Any]?)
    func processScreenEventFromBGQ(identifier: String, name: String, timestamp: String?, properties: [String: Any])
    func processEventFromBGQ(identifier: String, name: String, timestamp: String?, properties: [String: Any])
    func processDeleteTokenFromBGQ(identifier: String, token: String, timestamp: String)
    func processRegisterDeviceFromBGQ(identifier: String, token: String, timestamp: String, attributes: [String: Any]?)
    func processPushMetricsFromBGQ(token: String, event: Metric, deliveryId: String, timestamp: String, metaData: [String: Any])
}

public class DataPipeline: ModuleTopLevelObject<DataPipelineInstance>, DataPipelineInstance {
    /**
     ModuleTopLevelObject is intentionally designed to allow null implementations, matching our requirements overall. Customer who have correctly initialized the SDK will consistently find the implementation set correctly and operational. However, customers who attempt to use functions dependent on this implementation without initializing the SDK may not see the desired results, which is an expected behavior. To align our SDK with Segment API practices (e.g., add(Plugin)), which require returning non-null objects, we face a challenge when the SDK is not initialized.
     To avoid force unwrapping and to maintain consistency with Segment APIs, we’ve introduced a ‘dead instance’ to handle these edge cases. This implementation acts as a safeguard, capturing calls made without SDK initialization and logging a warning, yet it does not perform any operations for these calls. This approach ensures stability and consistency in the API’s behavior.
     */
    public var analytics: Segment.Analytics {
        implementation?.analytics ?? Analytics(configuration: Configuration(writeKey: "DEADINSTANCE"))
    }

    @CioInternalCommon.Atomic public private(set) static var shared = DataPipeline()
    @CioInternalCommon.Atomic public private(set) static var moduleConfig: DataPipelineConfigOptions!

    private static let moduleName = "DataPipeline"

    private init() {
        super.init(moduleName: Self.moduleName)
    }

    /**
     Initializes the shared `instance` of `DataPipeline`.
     This function is automatically called when the SDK initialization is called, which should ideally be done on app launch,
     before using any `DataPipeline` features.
     */
    @discardableResult
    public static func initialize(moduleConfig: DataPipelineConfigOptions) -> CustomerIOInstance {
        Self.moduleConfig = moduleConfig
        shared.initializeModule()
        return shared
    }

    private func initializeModule() {
        guard getImplementationInstance() == nil else {
            logger.info("\(moduleName) module is already initialized. Ignoring redundant initialization request.")
            return
        }

        logger.debug("Setting up \(moduleName) module...")
        let cdpImplementation = DataPipelineImplementation(diGraph: DIGraphShared.shared, moduleConfig: Self.moduleConfig)
        setImplementationInstance(implementation: cdpImplementation)

        logger.info("\(moduleName) module successfully set up with SDK")
    }

    // Code below this line will be updated in later PRs
    // TODO: [CDP] Review CustomerIOInstance here after finalizing DataPipelineImplementation

    public var siteId: String? { implementation?.siteId }

    public var config: CioInternalCommon.SdkConfig? { implementation?.config }

    public func identify(identifier: String, body: [String: Any]) {
        implementation?.identify(identifier: identifier, body: body)
    }

    public func identify<RequestBody: Codable>(identifier: String, body: RequestBody) {
        implementation?.identify(identifier: identifier, body: body)
    }

    public func identify(body: Codable) {
        implementation?.identify(body: body)
    }

    public var registeredDeviceToken: String? { implementation?.registeredDeviceToken }

    public func clearIdentify() {
        implementation?.clearIdentify()
    }

    public func track(name: String, data: [String: Any]) {
        implementation?.track(name: name, data: data)
    }

    public func track<RequestBody: Codable>(name: String, data: RequestBody?) {
        implementation?.track(name: name, data: data)
    }

    public func screen(name: String, data: [String: Any]) {
        implementation?.screen(name: name, data: data)
    }

    public func screen<RequestBody: Codable>(name: String, data: RequestBody?) {
        implementation?.screen(name: name, data: data)
    }

    public var profileAttributes: [String: Any] {
        get {
            implementation?.profileAttributes ?? [:]
        }
        set {
            alreadyCreatedImplementation?.profileAttributes = newValue
        }
    }

    public var deviceAttributes: [String: Any] {
        get {
            implementation?.deviceAttributes ?? [:]
        }
        set {
            alreadyCreatedImplementation?.deviceAttributes = newValue
        }
    }

    public func registerDeviceToken(_ deviceToken: String) {
        implementation?.registerDeviceToken(deviceToken)
    }

    public func deleteDeviceToken() {
        implementation?.deleteDeviceToken()
    }

    public func trackMetric(deliveryID: String, event: CioInternalCommon.Metric, deviceToken: String) {
        implementation?.trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken)
    }
}

// MARK: Background queue migration

public extension DataPipeline {
    func processIdentifyFromBGQ(identifier: String, timestamp: String, body: [String: Any]? = nil) {
        implementation?.processIdentifyFromBGQ(identifier: identifier, timestamp: timestamp, body: body)
    }

    func processScreenEventFromBGQ(identifier: String, name: String, timestamp: String?, properties: [String: Any]) {
        implementation?.processScreenEventFromBGQ(identifier: identifier, name: name, timestamp: timestamp, properties: properties)
    }

    func processEventFromBGQ(identifier: String, name: String, timestamp: String?, properties: [String: Any]) {
        implementation?.processEventFromBGQ(identifier: identifier, name: name, timestamp: timestamp, properties: properties)
    }

    func processDeleteTokenFromBGQ(identifier: String, token: String, timestamp: String) {
        implementation?.processDeleteTokenFromBGQ(identifier: identifier, token: token, timestamp: timestamp)
    }

    func processRegisterDeviceFromBGQ(identifier: String, token: String, timestamp: String, attributes: [String: Any]? = nil) {
        implementation?.processRegisterDeviceFromBGQ(identifier: identifier, token: token, timestamp: timestamp, attributes: attributes)
    }

    func processPushMetricsFromBGQ(token: String, event: Metric, deliveryId: String, timestamp: String, metaData: [String: Any] = [:]) {
        implementation?.processPushMetricsFromBGQ(token: token, event: event, deliveryId: deliveryId, timestamp: timestamp, metaData: metaData)
    }
}
