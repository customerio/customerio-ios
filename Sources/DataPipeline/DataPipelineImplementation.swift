import CioInternalCommon
import Segment

class DataPipelineImplementation: DataPipelineInstance {
    private let moduleConfig: DataPipelineConfigOptions
    private let logger: Logger
    let analytics: Analytics

    private var globalDataStore: GlobalDataStore
    private let deviceAttributesProvider: DeviceAttributesProvider
    private let dateUtil: DateUtil
    private let deviceInfo: DeviceInfo

    init(diGraph: DIGraphShared, moduleConfig: DataPipelineConfigOptions) {
        self.moduleConfig = moduleConfig
        self.logger = diGraph.logger
        self.analytics = .init(configuration: moduleConfig.toSegmentConfiguration())

        self.globalDataStore = diGraph.globalDataStore
        self.deviceAttributesProvider = diGraph.deviceAttributesProvider
        self.dateUtil = diGraph.dateUtil
        self.deviceInfo = diGraph.deviceInfo

        initialize()
    }

    private func initialize() {
        if let token = globalDataStore.pushDeviceToken {
            // if the device token exists, pass it to the plugin to ensure device attributes are updated with each request
            setDeviceToken(token)
        }
    }

    // Code below this line will be updated in later PRs
    // FIXME: [CDP] Implement CustomerIOInstance

    var siteId: String?

    var config: CioInternalCommon.SdkConfig?

    func identify(identifier: String, body: [String: Any]) {
        analytics.identify(userId: identifier, traits: body)
    }

    func identify<RequestBody: Codable>(identifier: String, body: RequestBody) {
        analytics.identify(userId: identifier, traits: body)
    }

    var registeredDeviceToken: String? {
        analytics.find(pluginType: DeviceAttributes.self)?.token
    }

    func clearIdentify() {
        // TODO: [CDP] CustomerIOImplementation also call deleteDeviceToken from clearIdentify, but customers using DataPipeline only,
        // we had to call this explicitly. Rethink on how can we make one call for both customers.
        removeDevicePlugin()
        analytics.reset()
    }

    func track(name: String, data: [String: Any]) {
        analytics.track(name: name, properties: data)
    }

    func track<RequestBody: Codable>(name: String, data: RequestBody?) {
        analytics.track(name: name, properties: data)
    }

    func screen(name: String, data: [String: Any]) {
        analytics.screen(title: name, properties: data)
    }

    func screen<RequestBody: Codable>(name: String, data: RequestBody?) {
        analytics.screen(title: name, properties: data)
    }

    var profileAttributes: [String: Any] {
        get { analytics.traits() ?? [:] }
        set {
            let userId = analytics.userId ?? analytics.anonymousId
            analytics.identify(userId: userId, traits: newValue)
        }
    }

    var deviceAttributes: [String: Any] {
        get {
            let attributesPlugin = analytics.find(pluginType: DeviceAttributes.self)
            return attributesPlugin?.attributes ?? [:]
        }
        set {
            let attributesPlugin = analytics.find(pluginType: DeviceAttributes.self)
            addDeviceAttributes(token: attributesPlugin?.token, attributes: newValue)
        }
    }

    /// Adds device default and custom attributes using DeviceAttributes plugin
    private func addDeviceAttributes(token deviceToken: String? = nil, attributes customAttributes: [String: Any] = [:]) {
        // Consolidate all Apple platforms under iOS
        let deviceOsName = "iOS"
        deviceAttributesProvider.getDefaultDeviceAttributes { defaultDeviceAttributes in
            let deviceAttributes: [String: Any] = defaultDeviceAttributes
                .mergeWith([
                    "platform": deviceOsName,
                    "lastUsed": self.dateUtil.now
                ])
                .mergeWith(customAttributes)

            // Make sure DeviceAttributes plugin is attached
            let attributesPlugin: DeviceAttributes
            if let plugin = self.analytics.find(pluginType: DeviceAttributes.self) {
                attributesPlugin = plugin
            } else {
                attributesPlugin = DeviceAttributes()
                self.analytics.add(plugin: attributesPlugin)
            }

            attributesPlugin.attributes = deviceAttributes
            attributesPlugin.token = deviceToken
        }
    }

    func registerDeviceToken(_ deviceToken: String) {
        logger.debug("storing device token to device storage \(deviceToken)")
        // save the device token for later use.
        // segment plugin doesn't store token anywhere so we need to pass token to it every time
        // storing it so we can reference the token and register on app relaunch
        globalDataStore.pushDeviceToken = deviceToken
        setDeviceToken(deviceToken)
    }

    /// Internal method for passing the device token to the plugin
    private func setDeviceToken(_ deviceToken: String) {
        logger.info("registering device token \(deviceToken)")

        addDeviceAttributes(token: deviceToken)
    }

    func deleteDeviceToken() {
        logger.info("deleting device token request made")

        // Do not delete push token from device storage. The token is valid
        // once given to SDK. We need it for future profile identifications.

        removeDevicePlugin()
    }

    /// Internal method for removing attached plugins to stop sending device token and attributes
    private func removeDevicePlugin() {
        // Remove DeviceAttributes plugin to avoid attaching token and attributes to every request.
        if let attributesPlugin = analytics.find(pluginType: DeviceAttributes.self) {
            analytics.remove(plugin: attributesPlugin)
            logger.info("DeviceAttributes plugin removed")
        }
    }

    func trackMetric(deliveryID: String, event: Metric, deviceToken: String) {
        // FIXME: [CDP] Update name to match the expectation
        let name = "Push Metric"
        let properties = MetricEvent(event: name, metric: event, deliveryId: deliveryID, deliveryToken: deviceToken)
        analytics.track(name: name, properties: properties)
    }
}
