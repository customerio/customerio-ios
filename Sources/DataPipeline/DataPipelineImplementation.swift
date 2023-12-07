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

    var profileAttributes: [String: Any] = [:]

    var deviceAttributes: [String: Any] = [:]

    func registerDeviceToken(_ deviceToken: String) {
        analytics.setDeviceToken(deviceToken)
    }

    func deleteDeviceToken() {
        fatalError("will be implemented later")
    }

    func trackMetric(deliveryID: String, event: CioInternalCommon.Metric, deviceToken: String) {
        fatalError("will be implemented later")
    }
}
