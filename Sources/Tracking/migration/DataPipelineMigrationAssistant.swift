import CioDataPipelines
import CioInternalCommon
import Foundation

// sourcery: InjectRegister = "DataPipelineMigrationAssistant"
// sourcery: InjectSingleton
/// Responsible for handling migration of pending tasks from `Tracking` module to `DataPipeline` module.
class DataPipelineMigrationAssistant {
    private let logger: Logger
    private let backgroundQueue: Queue
    private let jsonAdapter: JsonAdapter
    private let threadUtil: ThreadUtil

    /**
     Constructor for singleton, only.

     Try loading the credentials previously saved for the singleton instance.
     */
    init(
        logger: Logger,
        queue: Queue,
        jsonAdapter: JsonAdapter,
        threadUtil: ThreadUtil
    ) {
        self.logger = logger
        self.backgroundQueue = queue
        self.jsonAdapter = jsonAdapter
        self.threadUtil = threadUtil
    }

    func handleQueueBacklog() {
        let allStoredTasks = backgroundQueue.getAllStoredTasks()
        if allStoredTasks.count <= 0 {
            logger.info("CIO-CDP Migration: No tasks pending in the background queue to be executed.")
            return
        }
        threadUtil.runBackground { [weak self] in
            allStoredTasks.forEach { task in
                self?.getAndProcessTask(for: task)
            }
        }
    }

    /**
     Retrieves a task from the queue based on its metadata.
     Fetches `type` of the task and processes accordingly
     */
    func getAndProcessTask(for task: QueueTaskMetadata) {
        guard let taskDetail = backgroundQueue.getTaskDetail(task) else { return }
        let taskData = taskDetail.data
        let timestamp = taskDetail.timestamp.string(format: .iso8601noMilliseconds).toString()
        var isProcessed = true

        // Remove the task from the queue if the task has been processed successfully
        defer {
            if isProcessed {
//                backgroundQueue.deleteProcessedTask(task)
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
                DataPipeline.shared.processIdentifyFromBGQ(identifier: trackTaskData.identifier, timestamp: timestamp)
                return
            }
            guard let profileAttributes: [String: Any] = jsonAdapter.fromJsonString(trackTaskData.attributesJsonString!) else {
                DataPipeline.shared.processIdentifyFromBGQ(identifier: trackTaskData.identifier, timestamp: timestamp)
                return
            }
            DataPipeline.shared.processIdentifyFromBGQ(identifier: trackTaskData.identifier, timestamp: timestamp, body: profileAttributes)

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
            trackType.type == .screen ? DataPipeline.shared.processScreenEventFromBGQ(identifier: trackTaskData.identifier, name: trackType.name, timestamp: trackType.timestamp?.toString(), properties: properties)
                : DataPipeline.shared.processEventFromBGQ(identifier: trackTaskData.identifier, name: trackType.name, timestamp: trackType.timestamp?.toString(), properties: properties)

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
                DataPipeline.shared.processRegisterDeviceFromBGQ(identifier: registerPushTaskData.profileIdentifier, token: token, timestamp: timestamp, attributes: attributes)
            }
        // Processes delete device token
        case .deletePushToken:
            guard let deletePushData: DeletePushNotificationQueueTaskData = jsonAdapter.fromJson(taskData) else {
                isProcessed = false
                return
            }
            DataPipeline.shared.processDeleteTokenFromBGQ(identifier: deletePushData.profileIdentifier, token: deletePushData.deviceToken, timestamp: timestamp)

        // Processes push metrics
        case .trackPushMetric:
            guard let trackPushTaskData: MetricRequest = jsonAdapter.fromJson(taskData) else {
                isProcessed = false
                return
            }
            DataPipeline.shared.processPushMetricsFromBGQ(token: trackPushTaskData.deviceToken, event: trackPushTaskData.event, deliveryId: trackPushTaskData.deliveryId, timestamp: trackPushTaskData.timestamp.toString())
        }
    }
}
