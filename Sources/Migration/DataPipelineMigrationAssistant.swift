import CioInternalCommon
import Foundation

public protocol DataPipelineMigrationAction {
    func processAlreadyIdentifiedUser(identifier: String)
    func processIdentifyFromBGQ(identifier: String, timestamp: String, body: [String: Any]?)
    func processScreenEventFromBGQ(identifier: String, name: String, timestamp: String?, properties: [String: Any])
    func processEventFromBGQ(identifier: String, name: String, timestamp: String?, properties: [String: Any])
    func processDeleteTokenFromBGQ(identifier: String, token: String, timestamp: String)
    func processRegisterDeviceFromBGQ(identifier: String, token: String, timestamp: String, attributes: [String: Any]?)
    func processPushMetricsFromBGQ(token: String, event: Metric, deliveryId: String, timestamp: String, metaData: [String: Any])
}

public class DataPipelineMigrationAssistant {
    public var migrationHandler: DataPipelineMigrationAction
    private let logger: Logger
    private let backgroundQueue: Queue
    private let jsonAdapter: JsonAdapter
    private let threadUtil: ThreadUtil
    private var profileStore: ProfileStore

    public init(handler: DataPipelineMigrationAction, diGraph: DIGraph) {
        self.migrationHandler = handler
        self.logger = diGraph.logger
        self.backgroundQueue = diGraph.queue
        self.jsonAdapter = diGraph.jsonAdapter
        self.threadUtil = diGraph.threadUtil
        self.profileStore = diGraph.profileStore
    }

    // Only public method in this class that is accessible to other modules.
    // This method handles all the migration tasks present in the
    // Journeys background queue.
    public func performMigration(for userId: String?) {
        handleAlreadyIdentifiedMigratedUser(for: userId)
        handleQueueBacklog()
    }

    func handleAlreadyIdentifiedMigratedUser(for userId: String?) {
        // This code handles the scenario where a user migrates
        // from the Journeys module to the CDP module while already logged in.
        // This ensures the CDP module is informed about the
        // currently logged-in user for seamless processing of events.
        if userId == nil {
            if let identifier = profileStore.identifier {
                migrationHandler.processAlreadyIdentifiedUser(identifier: identifier)
                // Remove identifier from storage
                // so same profile can not be re-identifed
                profileStore.identifier = nil
            }
        }
    }

    func handleQueueBacklog(siteId: String) {
        let allStoredTasks = backgroundQueue.getAllStoredTasks(siteId: siteId)
        if allStoredTasks.count <= 0 {
            logger.info("CIO-CDP Migration: No tasks pending in the background queue to be executed.")
            return
        }
        threadUtil.runBackground { [weak self] in
            allStoredTasks.forEach { task in
                self?.getAndProcessTask(for: task, siteId: siteId)
            }
        }
    }

    /**
     Retrieves a task from the queue based on its metadata.
     Fetches `type` of the task and processes accordingly
     */
    func getAndProcessTask(for task: QueueTaskMetadata, siteId: String) {
        guard let taskDetail = backgroundQueue.getTaskDetail(task, siteId: siteId) else { return }
        let taskData = taskDetail.data
        let timestamp = taskDetail.timestamp.string(format: .iso8601WithMilliseconds)
        var isProcessed = true

        // Remove the task from the queue if the task has been processed successfully
        defer {
            if isProcessed {
                backgroundQueue.deleteProcessedTask(task, siteId: siteId)
            }
        }
        switch taskDetail.taskType {
        case .trackDeliveryMetric:
            // TODO: Segment doesn't provide this method by default needs to get added
            // Remove isProcessed when the method is added
            print("Track Delivery Metrics for in-app - Needs discussion")
            isProcessed = false

        // Processes identify profile and profile attributes
        case .identifyProfile:
            guard let trackTaskData: IdentifyProfileQueueTaskData = jsonAdapter.fromJson(taskData) else {
                isProcessed = false
                return
            }
            if let attributedString = trackTaskData.attributesJsonString, attributedString.contains("null") {
                migrationHandler.processIdentifyFromBGQ(identifier: trackTaskData.identifier, timestamp: timestamp, body: nil)
                return
            }
            guard let profileAttributes: [String: Any] = jsonAdapter.fromJsonString(trackTaskData.attributesJsonString!) else {
                migrationHandler.processIdentifyFromBGQ(identifier: trackTaskData.identifier, timestamp: timestamp, body: nil)
                return
            }
            migrationHandler.processIdentifyFromBGQ(identifier: trackTaskData.identifier, timestamp: timestamp, body: profileAttributes)

        // Process `screen` and `event` types
        case .trackEvent:
            guard let trackTaskData: TrackEventQueueTaskData = jsonAdapter.fromJson(taskData) else {
                isProcessed = false
                return
            }
            guard let trackType: TrackEventTypeForAnalytics = jsonAdapter.fromJson(trackTaskData.attributesJsonString.data) else {
                isProcessed = false
                return
            }
            var properties = [String: Any]()
            if let attributes: [String: Any] = jsonAdapter.fromJsonString(trackTaskData.attributesJsonString) {
                properties = attributes
            }
            let timestamp = trackType.timestamp?.string(format: .iso8601WithMilliseconds)
            trackType.type == .screen ? migrationHandler.processScreenEventFromBGQ(identifier: trackTaskData.identifier, name: trackType.name, timestamp: timestamp, properties: properties)
                : migrationHandler.processEventFromBGQ(identifier: trackTaskData.identifier, name: trackType.name, timestamp: timestamp, properties: properties)

        // Processes register device token and device attributes
        case .registerPushToken:
            guard let registerPushTaskData: RegisterPushNotificationQueueTaskData = jsonAdapter.fromJson(taskData) else {
                isProcessed = false
                return
            }
            guard let allAttributes: [String: Any] = jsonAdapter.fromJsonString(registerPushTaskData.attributesJsonString!) else {
                isProcessed = false
                return
            }
            guard let device = allAttributes["device"] as? [String: Any] else {
                isProcessed = false
                return
            }
            if let token = device["id"] as? String, let attributes = device["attributes"] as? [String: Any] {
                migrationHandler.processRegisterDeviceFromBGQ(identifier: registerPushTaskData.profileIdentifier, token: token, timestamp: timestamp, attributes: attributes)
            }
        // Processes delete device token
        case .deletePushToken:
            guard let deletePushData: DeletePushNotificationQueueTaskData = jsonAdapter.fromJson(taskData) else {
                isProcessed = false
                return
            }
            migrationHandler.processDeleteTokenFromBGQ(identifier: deletePushData.profileIdentifier, token: deletePushData.deviceToken, timestamp: timestamp)

        // Processes push metrics
        case .trackPushMetric:
            guard let trackPushTaskData: MetricRequest = jsonAdapter.fromJson(taskData) else {
                isProcessed = false
                return
            }
            migrationHandler.processPushMetricsFromBGQ(token: trackPushTaskData.deviceToken, event: trackPushTaskData.event, deliveryId: trackPushTaskData.deliveryId, timestamp: trackPushTaskData.timestamp.string(format: .iso8601WithMilliseconds), metaData: [:])
        }
    }
}
