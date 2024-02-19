import CioInternalCommon
import CioTrackingMigration
import Foundation

// This class handles all the migration methods to process
// the unprocessed tasks from background queue coming from
// tracking module.
class DataPipelineMigrationHandler: DataPipelineMigrationAction {
    let implementation: DataPipelineInstance
    init(implementation: DataPipelineInstance) {
        self.implementation = implementation
    }

    func processAlreadyIdentifiedUser(identifier: String) {
        DataPipeline.shared.identify(identifier: identifier, body: [:])
    }

    func processIdentifyFromBGQ(identifier: String, timestamp: String, body: [String: Any]? = nil) {
        implementation.processIdentifyFromBGQ(identifier: identifier, timestamp: timestamp, body: body)
    }

    func processScreenEventFromBGQ(identifier: String, name: String, timestamp: String?, properties: [String: Any]) {
        implementation.processScreenEventFromBGQ(identifier: identifier, name: name, timestamp: timestamp, properties: properties)
    }

    func processEventFromBGQ(identifier: String, name: String, timestamp: String?, properties: [String: Any]) {
        implementation.processEventFromBGQ(identifier: identifier, name: name, timestamp: timestamp, properties: properties)
    }

    func processDeleteTokenFromBGQ(identifier: String, token: String, timestamp: String) {
        implementation.processDeleteTokenFromBGQ(identifier: identifier, token: token, timestamp: timestamp)
    }

    func processRegisterDeviceFromBGQ(identifier: String, token: String, timestamp: String, attributes: [String: Any]?) {
        implementation.processRegisterDeviceFromBGQ(identifier: identifier, token: token, timestamp: timestamp, attributes: attributes)
    }

    func processPushMetricsFromBGQ(token: String, event: Metric, deliveryId: String, timestamp: String, metaData: [String: Any]) {
        implementation.processPushMetricsFromBGQ(token: token, event: event, deliveryId: deliveryId, timestamp: timestamp, metaData: metaData)
    }
}
