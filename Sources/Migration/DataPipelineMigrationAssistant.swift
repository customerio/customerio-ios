import CioInternalCommon
import Foundation

public protocol DataPipelineMigrationAction: AutoMockable {
    func processAlreadyIdentifiedUser(identifier: String)
    func processIdentifyFromBGQ(identifier: String, timestamp: String, body: [String: Any]?)
    func processScreenEventFromBGQ(identifier: String, name: String, timestamp: String?, properties: [String: Any])
    func processEventFromBGQ(identifier: String, name: String, timestamp: String?, properties: [String: Any])
    func processDeleteTokenFromBGQ(identifier: String, token: String, timestamp: String)
    func processRegisterDeviceFromBGQ(identifier: String, token: String, timestamp: String, attributes: [String: Any]?)
    func processMetricsFromBGQ(token: String?, event: String, deliveryId: String, timestamp: String, metaData: [String: Any])
}

public class DataPipelineMigrationAssistant {
    public var migrationHandler: DataPipelineMigrationAction
    private let logger: Logger
    private let backgroundQueue: Queue
    private let jsonAdapter: JsonAdapter
    private let threadUtil: ThreadUtil
    private var profileStore: ProfileStore

    public init(handler: DataPipelineMigrationAction) {
        self.migrationHandler = handler
        self.logger = DIGraphShared.shared.logger
        self.backgroundQueue = DIGraphShared.shared.queue
        self.jsonAdapter = DIGraphShared.shared.jsonAdapter
        self.threadUtil = DIGraphShared.shared.threadUtil
        self.profileStore = DIGraphShared.shared.profileStore
    }

    // Only public method in this class that is accessible to other modules.
    // This method handles all the migration tasks present in the
    // Journeys background queue.
    public func performMigration(siteId: String) {
        handleAlreadyIdentifiedMigratedUser(siteId: siteId)
        handleQueueBacklog(siteId: siteId)
    }

    func handleAlreadyIdentifiedMigratedUser(siteId: String) {
        // This code handles the scenario where a user migrates
        // from the Journeys module to the CDP module while already logged in.
        // This ensures the CDP module is informed about the
        // currently logged-in user for seamless processing of events.
        if let identifier = profileStore.getProfileId(siteId: siteId) {
            migrationHandler.processAlreadyIdentifiedUser(identifier: identifier)
            // Remove identifier from storage
            // so same profile can not be re-identifed
            profileStore.deleteProfileId(siteId: siteId)
        }
    }

    func handleQueueBacklog(siteId: String) {
        let allStoredTasks = backgroundQueue.getAllStoredTasks(siteId: siteId)
        if allStoredTasks.count <= 0 {
            logger.info("CIO-CDP Migration: No tasks pending in the background queue to be executed.")
            return
        }
        threadUtil.runBackground {
            allStoredTasks.forEach { task in
                self.getAndProcessTask(for: task, siteId: siteId)
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
        var isProcessed = false

        switch taskDetail.taskType {
        case .trackDeliveryMetric:
            isProcessed = processTrackDeliveryMetric(taskData: taskData, timestamp: timestamp)
        case .identifyProfile:
            isProcessed = processIdentifyProfile(taskData: taskData, timestamp: timestamp)
        case .trackEvent:
            isProcessed = processTrackEvent(taskData: taskData, timestamp: timestamp)
        case .registerPushToken:
            isProcessed = processRegisterPushToken(taskData: taskData, timestamp: timestamp)
        case .deletePushToken:
            isProcessed = processDeletePushToken(taskData: taskData, timestamp: timestamp)
        case .trackPushMetric:
            isProcessed = processTrackPushMetric(taskData: taskData, timestamp: timestamp)
        }

        // Remove the task from the queue if the task has been processed successfully
        if isProcessed {
            backgroundQueue.deleteProcessedTask(task, siteId: siteId)
        }
    }

    // Processes in-app metric tracking
    private func processTrackDeliveryMetric(taskData: Data, timestamp: String) -> Bool {
        guard let trackInappTaskData: TrackDeliveryEventRequestBody = jsonAdapter.fromJson(taskData) else {
            return false
        }
        let payload = trackInappTaskData.payload
        migrationHandler.processMetricsFromBGQ(token: nil, event: payload.event.rawValue, deliveryId: payload.deliveryId, timestamp: timestamp, metaData: payload.metaData)
        return true
    }

    // Processes identify profile and profile attributes
    private func processIdentifyProfile(taskData: Data, timestamp: String) -> Bool {
        guard let trackTaskData: IdentifyProfileQueueTaskData = jsonAdapter.fromJson(taskData) else {
            return false
        }

        // If there are no profile attributes or profile attributes not in a valid format, JSON adapter will return nil and we will perform a migration without the profile attributes.
        guard let profileAttributesString: String = trackTaskData.attributesJsonString, let profileAttributes: [String: Any] = jsonAdapter.fromJsonString(profileAttributesString) else {
            migrationHandler.processIdentifyFromBGQ(identifier: trackTaskData.identifier, timestamp: timestamp, body: nil)
            return true
        }

        migrationHandler.processIdentifyFromBGQ(identifier: trackTaskData.identifier, timestamp: timestamp, body: profileAttributes)

        return true
    }

    // Process `screen` and `event` types
    private func processTrackEvent(taskData: Data, timestamp: String) -> Bool {
        guard let trackTaskData: TrackEventQueueTaskData = jsonAdapter.fromJson(taskData) else {
            return false
        }
        guard let trackType: TrackEventTypeForAnalytics = jsonAdapter.fromJson(trackTaskData.attributesJsonString.data) else {
            return false
        }
        var properties = [String: Any]()
        if let attributes: [String: Any] = jsonAdapter.fromJsonString(trackTaskData.attributesJsonString) {
            properties = attributes
        }
        let timestamp = trackType.timestamp?.string(format: .iso8601WithMilliseconds)

        if trackType.type == .screen {
            migrationHandler.processScreenEventFromBGQ(identifier: trackTaskData.identifier, name: trackType.name, timestamp: timestamp, properties: properties)
        } else {
            migrationHandler.processEventFromBGQ(identifier: trackTaskData.identifier, name: trackType.name, timestamp: timestamp, properties: properties)
        }
        return true
    }

    // Processes register device token and device attributes
    private func processRegisterPushToken(taskData: Data, timestamp: String) -> Bool {
        guard let registerPushTaskData: RegisterPushNotificationQueueTaskData = jsonAdapter.fromJson(taskData) else {
            return false
        }
        guard let attributesJsonString = registerPushTaskData.attributesJsonString, let allAttributes: [String: Any] = jsonAdapter.fromJsonString(attributesJsonString) else {
            return false
        }
        guard let device = allAttributes["device"] as? [String: Any] else {
            return false
        }
        if let token = device["id"] as? String, let attributes = device["attributes"] as? [String: Any] {
            migrationHandler.processRegisterDeviceFromBGQ(identifier: registerPushTaskData.profileIdentifier, token: token, timestamp: timestamp, attributes: attributes)
        }
        return true
    }

    // Processes delete device token
    private func processDeletePushToken(taskData: Data, timestamp: String) -> Bool {
        guard let deletePushData: DeletePushNotificationQueueTaskData = jsonAdapter.fromJson(taskData) else {
            return false
        }
        migrationHandler.processDeleteTokenFromBGQ(identifier: deletePushData.profileIdentifier, token: deletePushData.deviceToken, timestamp: timestamp)
        return true
    }

    // Processes push metrics
    private func processTrackPushMetric(taskData: Data, timestamp: String) -> Bool {
        guard let trackPushTaskData: MetricRequest = jsonAdapter.fromJson(taskData) else {
            return false
        }
        migrationHandler.processMetricsFromBGQ(token: trackPushTaskData.deviceToken, event: trackPushTaskData.event.rawValue, deliveryId: trackPushTaskData.deliveryId, timestamp: trackPushTaskData.timestamp.string(format: .iso8601WithMilliseconds), metaData: [:])
        return true
    }
}
