import CioInternalCommon
import Segment

class DataPipelineImplementation: DataPipelineInstance {
    let moduleConfig: DataPipelineConfigOptions
    let logger: Logger
    let analytics: Analytics

    init(diGraph: DIGraphShared, moduleConfig: DataPipelineConfigOptions) {
        self.moduleConfig = moduleConfig
        self.logger = diGraph.logger
        self.analytics = .init(configuration: moduleConfig.toSegmentConfiguration())
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

    var registeredDeviceToken: String?

    func clearIdentify() {
        fatalError("will be implemented later")
    }

    func track(name: String, data: [String: Any]) {
        fatalError("will be implemented later")
    }

    func track<RequestBody: Codable>(name: String, data: RequestBody?) {
        fatalError("will be implemented later")
    }

    func screen(name: String, data: [String: Any]) {
        fatalError("will be implemented later")
    }

    func screen<RequestBody: Codable>(name: String, data: RequestBody?) {
        fatalError("will be implemented later")
    }

    var profileAttributes: [String: Any] = [:]

    var deviceAttributes: [String: Any] = [:]

    func registerDeviceToken(_ deviceToken: String) {
        fatalError("will be implemented later")
    }

    func deleteDeviceToken() {
        fatalError("will be implemented later")
    }

    func trackMetric(deliveryID: String, event: CioInternalCommon.Metric, deviceToken: String) {
        fatalError("will be implemented later")
    }

    @discardableResult
    func add(plugin: Plugin) -> Plugin {
        analytics.add(plugin: plugin)
    }

    @discardableResult
    func add(enrichment: @escaping EnrichmentClosure) -> Plugin {
        analytics.add(enrichment: enrichment)
    }

    func find<T: Plugin>(pluginType: T.Type) -> T? {
        analytics.find(pluginType: pluginType)
    }
}
