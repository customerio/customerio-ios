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

    func handleQueueBacklog() {
        let allStoredTasks = backgroundQueue.getAllStoredTasks()
        if allStoredTasks.count <= 0 {
            logger.info("No tasks pending in the background queue to be executed.")
            return
        }

        threadUtil.runBackground { [weak self] in
            allStoredTasks.forEach { task in
                self?.getStoredTask(for: task)
            }
        }
    }

    // TODO: Pending: Clean this method + device attributes + clean individual way to delete processed tasks
    func getStoredTask(for task: QueueTaskMetadata) {
        guard let taskDetail = backgroundQueue.getTaskDetail(task) else { return }
        let taskData = taskDetail.data

        switch taskDetail.taskType {
        case .trackDeliveryMetric:
            // TODO: Segment doesn't provide this method by default needs to get added
            print("Track Delivery Metrics for in-app - Needs discussion")
        case .identifyProfile:
            guard let trackTaskData: IdentifyProfileQueueTaskData = jsonAdapter.fromJson(taskData) else {
                return
            }
            if let attributedString = trackTaskData.attributesJsonString, attributedString.contains("null") {
                identify(identifier: trackTaskData.identifier)
                return
            }
            guard let profileAttributes: [String: Any] = jsonAdapter.fromJsonString(trackTaskData.attributesJsonString!) else {
                identify(identifier: trackTaskData.identifier)
                return
            }
            identify(identifier: trackTaskData.identifier, body: profileAttributes)
            backgroundQueue.deleteProcessedTask(task)
        case .trackEvent:
            guard let trackTaskData: TrackEventQueueTaskData = jsonAdapter.fromJson(taskData) else { return }
            guard let trackType: TrackEventTypeForAnalytics = jsonAdapter.fromJson(trackTaskData.attributesJsonString.data) else { return }
            switch trackType.type {
            case .screen:
                screen(name: trackType.name, data: trackTaskData)
            case .event:
                track(name: trackType.name, data: trackTaskData)
            }
            backgroundQueue.deleteProcessedTask(task)
        case .registerPushToken:
            guard let registerPushTaskData: RegisterPushNotificationQueueTaskData = jsonAdapter.fromJson(taskData) else { return }
            guard let deviceAttributes: [String: Any] = jsonAdapter.fromJsonString(registerPushTaskData.attributesJsonString!) else { return }
            guard let device = deviceAttributes["device"] as? [String: Any] else { return }
            self.deviceAttributes = device
            backgroundQueue.deleteProcessedTask(task)
        case .deletePushToken:
            deleteDeviceToken()
            backgroundQueue.deleteProcessedTask(task)
        case .trackPushMetric:
            guard let trackPushTaskData: MetricRequest = jsonAdapter.fromJson(taskData) else { return }
            trackMetric(deliveryID: trackPushTaskData.deliveryId, event: trackPushTaskData.event, deviceToken: trackPushTaskData.deviceToken)
            backgroundQueue.deleteProcessedTask(task)
        }
    }
}
