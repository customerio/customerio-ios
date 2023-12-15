import CioInternalCommon
import Segment

class DataPipelineImplementation: DataPipelineInstance {
    let moduleConfig: DataPipelineConfigOptions
    let logger: Logger
    let analytics: Analytics
    let busEventManager: EventBusHandler

    init(diGraph: DIGraphShared, moduleConfig: DataPipelineConfigOptions) {
        self.moduleConfig = moduleConfig
        self.logger = diGraph.logger
        self.analytics = .init(configuration: moduleConfig.toSegmentConfiguration())
        self.busEventManager = diGraph.eventBusHandler
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
        busEventManager.postEvent(ProfileIdentifiedEvent(identifier: identifier))
    }

    var registeredDeviceToken: String? {
        analytics.find(pluginType: DeviceToken.self)?.token
    }

    func clearIdentify() {
        // TODO: [CDP] CustomerIOImplementation also call deleteDeviceToken from clearIdentify, but customers using DataPipeline only,
        // we had to call this explicitly. Rethink on how can we make one call for both customers.
        busEventManager.postEvent(ResetEvent())
        deleteDeviceToken()
        analytics.reset()
    }

    func track(name: String, data: [String: Any]) {
        analytics.track(name: name, properties: data)
    }

    func track<RequestBody: Codable>(name: String, data: RequestBody?) {
        analytics.track(name: name, properties: data)
    }

    func screen(name: String, data: [String: Any]) {
        busEventManager.postEvent(ScreenViewedEvent(name: name))
        analytics.screen(title: name, properties: data)
    }

    func screen<RequestBody: Codable>(name: String, data: RequestBody?) {
        busEventManager.postEvent(ScreenViewedEvent(name: name))

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
            if let attributesPlugin = analytics.find(pluginType: DeviceAttributes.self) {
                attributesPlugin.attributes = newValue
            } else {
                // TODO: [CDP] Verify with server's expectation
                let attributesPlugin = DeviceAttributes()
                attributesPlugin.attributes = newValue
                analytics.add(plugin: attributesPlugin)
            }
        }
    }

    func registerDeviceToken(_ deviceToken: String) {
        analytics.setDeviceToken(deviceToken)
    }

    func deleteDeviceToken() {
        // Remove DeviceToken plugin to prevent attaching the token to every request
        if let tokenPlugin = analytics.find(pluginType: DeviceToken.self) {
            analytics.remove(plugin: tokenPlugin)
        }

        // Remove DeviceAttributes plugin to avoid attaching attributes to every request.
        if let attributesPlugin = analytics.find(pluginType: DeviceAttributes.self) {
            attributesPlugin.attributes = nil
            analytics.remove(plugin: attributesPlugin)
        }
    }

    func trackMetric(deliveryID: String, event: Metric, deviceToken: String) {
        // FIXME: [CDP] Update name to match the expectation
        let name = "Push Metric"
        let properties = MetricEvent(event: name, metric: event, deliveryId: deliveryID, deliveryToken: deviceToken)
        analytics.track(name: name, properties: properties)
    }
}
