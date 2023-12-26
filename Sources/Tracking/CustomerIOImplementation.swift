import CioDataPipelines
import CioInternalCommon
import Foundation

/**
 Because of `CustomerIO.shared` being a singleton API, there is always a use-case
 of calling any of the public functions on `CustomerIO` class *before* the SDK has
 been initialized. To make this use case easy to handle, we separate the logic of
 the CustomerIO class into this class. Therefore, it's assumed that as long as
 there is an instance of `CustomerIOImplementation` present, the SDK has been
 initialized successfully.
 */
// TODO: revisit if its still needed at the end
class CustomerIOImplementation: CustomerIOInstance {
    public var siteId: String? {
        sdkConfig.siteId
    }

    private let backgroundQueue: Queue
    private let jsonAdapter: JsonAdapter
    private var profileStore: ProfileStore
    private var hooks: HooksManager
    private let logger: Logger
    private var globalDataStore: GlobalDataStore
    private let sdkConfig: SdkConfig
    private let threadUtil: ThreadUtil

    static var autoScreenViewBody: (() -> [String: Any])?

    /**
     Constructor for singleton, only.

     Try loading the credentials previously saved for the singleton instance.
     */
    init(diGraph: DIGraph) {
        self.backgroundQueue = diGraph.queue
        self.jsonAdapter = diGraph.jsonAdapter
        self.profileStore = diGraph.profileStore
        self.hooks = diGraph.hooksManager
        self.logger = diGraph.logger
        self.globalDataStore = diGraph.globalDataStore
        self.sdkConfig = diGraph.sdkConfig
        self.threadUtil = diGraph.threadUtil
        DataPipeline.initialize(moduleConfig: DataPipelineConfigOptions.Factory.create(sdkConfig: sdkConfig))
    }

    public var config: SdkConfig? {
        sdkConfig
    }

    public var profileAttributes: [String: Any] {
        get { DataPipeline.shared.profileAttributes }
        set { DataPipeline.shared.profileAttributes = newValue }
    }

    public var deviceAttributes: [String: Any] {
        get { DataPipeline.shared.deviceAttributes }
        set { DataPipeline.shared.deviceAttributes = newValue }
    }

    public var registeredDeviceToken: String? {
        DataPipeline.shared.registeredDeviceToken
    }

    public func identify<RequestBody: Codable>(
        identifier: String,
        body: RequestBody
    ) {
        DataPipeline.shared.identify(identifier: identifier, body: body)
    }

    public func identify(body: Codable) {
        DataPipeline.shared.identify(body: body)
    }

    public func identify(identifier: String, body: [String: Any]) {
        DataPipeline.shared.identify(identifier: identifier, body: body)
    }

    public func clearIdentify() {
        DataPipeline.shared.clearIdentify()
    }

    public func track<RequestBody: Codable>(
        name: String,
        data: RequestBody?
    ) {
        DataPipeline.shared.track(name: name, data: data)
    }

    public func track(name: String, data: [String: Any]) {
        DataPipeline.shared.track(name: name, data: data)
    }

    public func screen(name: String, data: [String: Any]) {
        DataPipeline.shared.screen(name: name, data: data)
        hooks.screenViewHooks.forEach { hook in
            hook.screenViewed(name: name)
        }
    }

    public func screen<RequestBody: Codable>(
        name: String,
        data: RequestBody
    ) {
        DataPipeline.shared.screen(name: name, data: data)
        hooks.screenViewHooks.forEach { hook in
            hook.screenViewed(name: name)
        }
    }

    /**
     Register a new device token with Customer.io, associated with the current active customer. If there
     is no active customer, this will fail to register the device
     */
    public func registerDeviceToken(_ deviceToken: String) {
        DataPipeline.shared.registerDeviceToken(deviceToken)
    }

    /**
     Delete the currently registered device token
     */
    public func deleteDeviceToken() {
        DataPipeline.shared.deleteDeviceToken()
    }

    /**
     Track a push metric
     */
    public func trackMetric(
        deliveryID: String,
        event: Metric,
        deviceToken: String
    ) {
        DataPipeline.shared.trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken)
    }

    // TODO: Write test case
    func handleQueueBacklog() {
        let allStoredTasks = backgroundQueue.getAllStoredTasks()
        if allStoredTasks.count <= 0 {
            logger.info("No tasks pending in the background queue to be executed.")
            return
        }
        threadUtil.runBackground { [weak self] in
            allStoredTasks.forEach { task in
                self?.getAndProcessTask(for: task)
            }
        }
    }

    // TODO: Write test case
    /**
     Retrieves a task from the queue based on its metadata.
     Fetches `type` of the task and processes accordingly
     */
    func getAndProcessTask(for task: QueueTaskMetadata) {
        guard let taskDetail = backgroundQueue.getTaskDetail(task) else { return }
        let taskData = taskDetail.data
        var isProcessed = true
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
                DataPipeline.shared.processIdentifyFromBGQ(identifier: trackTaskData.identifier)
                return
            }
            guard let profileAttributes: [String: Any] = jsonAdapter.fromJsonString(trackTaskData.attributesJsonString!) else {
                DataPipeline.shared.processIdentifyFromBGQ(identifier: trackTaskData.identifier)
                return
            }
            DataPipeline.shared.processIdentifyFromBGQ(identifier: trackTaskData.identifier, body: profileAttributes)

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
                DataPipeline.shared.processRegisterDeviceFromBGQ(identifier: registerPushTaskData.profileIdentifier, token: token, attributes: attributes)
            }
        // Processes delete device token
        case .deletePushToken:
            guard let deletePushData: DeletePushNotificationQueueTaskData = jsonAdapter.fromJson(taskData) else {
                isProcessed = false
                return
            }
            DataPipeline.shared.processDeleteTokenFromBGQ(identifier: deletePushData.profileIdentifier, token: deletePushData.deviceToken)

        // Processes push metrics
        case .trackPushMetric:
            guard let trackPushTaskData: MetricRequest = jsonAdapter.fromJson(taskData) else {
                isProcessed = false
                return
            }
            DataPipeline.shared.processPushMetricsFromBGQ(token: trackPushTaskData.deviceToken, event: trackPushTaskData.event, deliveryId: trackPushTaskData.deliveryId, timestamp: trackPushTaskData.timestamp.toString())
        }

        // Remove the task from the queue if the task has been processed successfully
        if isProcessed {
            backgroundQueue.deleteProcessedTask(task)
        }
    }
}
