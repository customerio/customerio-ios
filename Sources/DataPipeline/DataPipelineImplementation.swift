import CioInternalCommon
import Segment

class DataPipelineImplementation: CustomerIOInstance {
    let moduleConfig: DataPipelineConfigOptions
    let logger: Logger
    let analytics: Analytics
    let jsonAdapter: JsonAdapter

    init(diGraph: DIGraphShared, moduleConfig: DataPipelineConfigOptions) {
        self.moduleConfig = moduleConfig
        self.logger = diGraph.logger
        self.analytics = .init(configuration: moduleConfig.toSegmentConfiguration())
        self.jsonAdapter = diGraph.jsonAdapter
    }

    // Code below this line will be updated in later PRs
    // FIXME: [CDP] Implement CustomerIOInstance

    var siteId: String?

    var config: CioInternalCommon.SdkConfig?

    func identify(identifier: String, body: [String: Any]) {
        fatalError("will be implemented later")
    }

    func identify<RequestBody>(identifier: String, body: RequestBody) where RequestBody: Encodable {
        analytics.identify(userId: identifier, traits: jsonAdapter.toJson(body))
    }

    var registeredDeviceToken: String?

    func clearIdentify() {
        fatalError("will be implemented later")
    }

    func track(name: String, data: [String: Any]) {
        fatalError("will be implemented later")
    }

    func track<RequestBody>(name: String, data: RequestBody?) where RequestBody: Encodable {
        fatalError("will be implemented later")
    }

    func screen(name: String, data: [String: Any]) {
        fatalError("will be implemented later")
    }

    func screen<RequestBody>(name: String, data: RequestBody?) where RequestBody: Encodable {
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
}
