import CioInternalCommon
import Segment

public protocol DataPipelineInstance: CustomerIOInstance, DataPipelinePlugin {
    func find<T: Plugin>(pluginType: T.Type) -> T?
}

public class DataPipeline: ModuleTopLevelObject<DataPipelineInstance>, DataPipelineInstance {
    @CioInternalCommon.Atomic public private(set) static var shared = DataPipeline()
    @CioInternalCommon.Atomic public private(set) static var moduleConfig: DataPipelineConfigOptions!
    private static let moduleName = "DataPipeline"

    private init() {
        super.init(moduleName: Self.moduleName)
    }

    /**
     Initialize the shared `instance` of `DataPipeline`.
     Call this function when your app launches, before using `DataPipeline.shared`.
     */
    @discardableResult
    public static func initialize(
        writeKey: String,
        configure configureHandler: ((inout DataPipelineConfigOptions) -> Void)? = nil
    ) -> CustomerIOInstance {
        var configOptions = moduleConfig ?? DataPipelineConfigOptions.Factory.create(writeKey: writeKey)

        if let configureHandler = configureHandler {
            configureHandler(&configOptions)
        }

        shared.initializeModule()
        return shared
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

    public func find<T: Segment.Plugin>(pluginType: T.Type) -> T? {
        implementation?.find(pluginType: pluginType)
    }
}
