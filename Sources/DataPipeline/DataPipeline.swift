import CioAnalytics
import CioInternalCommon
import CioTrackingMigration

public protocol DataPipelineInstance: CustomerIOInstance, DataPipelineMigrationAction {
    var analytics: Analytics { get }
}

public class DataPipeline: ModuleTopLevelObject<DataPipelineInstance>, DataPipelineInstance {
    /**
     ModuleTopLevelObject is intentionally designed to allow null implementations, matching our requirements overall. Customer who have correctly initialized the SDK will consistently find the implementation set correctly and operational. However, customers who attempt to use functions dependent on this implementation without initializing the SDK may not see the desired results, which is an expected behavior. To align our SDK with Segment API practices (e.g., add(Plugin)), which require returning non-null objects, we face a challenge when the SDK is not initialized.
     To avoid force unwrapping and to maintain consistency with Segment APIs, we’ve introduced a ‘dead instance’ to handle these edge cases. This implementation acts as a safeguard, capturing calls made without SDK initialization and logging a warning, yet it does not perform any operations for these calls. This approach ensures stability and consistency in the API’s behavior.
     */
    public var analytics: CioAnalytics.Analytics {
        implementation?.analytics ?? Analytics(configuration: Configuration(writeKey: "DEADINSTANCE"))
    }

    @CioInternalCommon.Atomic public private(set) static var shared = DataPipeline()
    @CioInternalCommon.Atomic public private(set) static var moduleConfig: DataPipelineConfigOptions!

    private static let moduleName = "DataPipeline"

    private init() {
        super.init(moduleName: Self.moduleName)
    }

    #if DEBUG
    // Methods to set up the test environment.
    // In unit tests, any implementation of the interface works, while integration tests use the actual implementation.

    @discardableResult
    public static func setUpSharedInstanceForUnitTest(implementation: DataPipelineInstance, config: DataPipelineConfigOptions) -> DataPipelineInstance {
        // initialize static properties before implementation creation, as they may be directly used by other classes
        moduleConfig = config
        shared._implementation = implementation

        return implementation
    }

    @discardableResult
    public static func setUpSharedInstanceForIntegrationTest(diGraphShared: DIGraphShared, config: DataPipelineConfigOptions) -> DataPipelineInstance {
        let implementation = DataPipelineImplementation(diGraph: diGraphShared, moduleConfig: config)
        return setUpSharedInstanceForUnitTest(implementation: implementation, config: config)
    }

    static func resetTestEnvironment() {
        moduleConfig = nil
        shared = DataPipeline()
    }
    #endif

    /**
     Initializes the shared `instance` of `DataPipeline`.
     This function is automatically called when the SDK initialization is called, which should ideally be done on app launch,
     before using any `DataPipeline` features.
     */
    @discardableResult
    public static func initialize(moduleConfig: DataPipelineConfigOptions) -> DataPipelineInstance {
        shared.initializeModuleIfNotAlready {
            Self.moduleConfig = moduleConfig

            return DataPipelineImplementation(diGraph: DIGraphShared.shared, moduleConfig: moduleConfig)
        }

        return shared
    }

    // MARK: - DataPipelineInstance implementation

    public var profileAttributes: [String: Any] {
        get { implementation?.profileAttributes ?? [:] }
        set {
            guard var implementation = implementation else { return }

            implementation.profileAttributes = newValue
        }
    }

    public func identify(userId: String, traits: [String: Any]?) {
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
        set {
            guard var implementation = implementation else { return }

            implementation.deviceAttributes = newValue
        }
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

    public func track(name: String, properties: [String: Any]?) {
        implementation?.track(name: name, properties: properties)
    }

    public func track<RequestBody: Codable>(name: String, properties: RequestBody?) {
        implementation?.track(name: name, properties: properties)
    }

    public func screen(title: String, properties: [String: Any]?) {
        implementation?.screen(title: title, properties: properties)
    }

    public func screen<RequestBody: Codable>(title: String, properties: RequestBody?) {
        implementation?.screen(title: title, properties: properties)
    }

    public func trackMetric(deliveryID: String, event: Metric, deviceToken: String) {
        implementation?.trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken)
    }
}

// MARK: Background queue migration

public extension DataPipeline {
    func processAlreadyIdentifiedUser(identifier: String) {
        implementation?.processAlreadyIdentifiedUser(identifier: identifier)
    }

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

    func processMetricsFromBGQ(token: String?, event: String, deliveryId: String, timestamp: String, metaData: [String: Any] = [:]) {
        implementation?.processMetricsFromBGQ(token: token, event: event, deliveryId: deliveryId, timestamp: timestamp, metaData: metaData)
    }
}
