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
    private let deviceAttributesProvider: DeviceAttributesProvider
    private let dateUtil: DateUtil
    private let deviceInfo: DeviceInfo

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
        self.deviceAttributesProvider = diGraph.deviceAttributesProvider
        self.dateUtil = diGraph.dateUtil
        self.deviceInfo = diGraph.deviceInfo

        DataPipeline.initialize(moduleConfig: DataPipelineConfigOptions.Factory.create(sdkConfig: sdkConfig))
    }

    public var config: SdkConfig? {
        sdkConfig
    }

    public var profileAttributes: [String: Any] {
        get {
            [:]
        }
        set {
            guard let existingProfileIdentifier = profileStore.identifier else {
                return
            }
            identify(identifier: existingProfileIdentifier, body: newValue)
        }
    }

    public var deviceAttributes: [String: Any] {
        get {
            [:]
        }
        set {
            guard let deviceToken = globalDataStore.pushDeviceToken else { return }
            let attributes = newValue
            addDeviceAttributes(deviceToken: deviceToken, customAttributes: attributes)
        }
    }

    public var registeredDeviceToken: String? {
        globalDataStore.pushDeviceToken
    }

    public func identify<RequestBody: Codable>(
        identifier: String,
        body: RequestBody
    ) {
        handleCommonIdentificationTasks(identifier: identifier, codableBody: body)
    }

    public func identify(identifier: String, body: [String: Any]) {
        handleCommonIdentificationTasks(identifier: identifier, dictionaryBody: body)
    }

    func handleCommonIdentificationTasks(identifier: String, dictionaryBody: [String: Any]? = nil, codableBody: Codable? = nil) {
        if identifier.isBlankOrEmpty() {
            logger.error("profile cannot be identified: Identifier is empty. Please retry with a valid, non-empty identifier.")
            return
        }

        // Check which body is non-nil and proceed accordingly
        if let body = dictionaryBody {
            DataPipeline.shared.identify(identifier: identifier, body: body)
        } else if let body = codableBody {
            DataPipeline.shared.identify(identifier: identifier, body: body)
        } else {
            DataPipeline.shared.identify(identifier: identifier)
        }

        let currentlyIdentifiedProfileIdentifier = profileStore.identifier
        let isChangingIdentifiedProfile = currentlyIdentifiedProfileIdentifier != nil &&
            currentlyIdentifiedProfileIdentifier != identifier
        let isFirstTimeIdentifying = currentlyIdentifiedProfileIdentifier == nil

        if let currentlyIdentifiedProfileIdentifier = currentlyIdentifiedProfileIdentifier,
           isChangingIdentifiedProfile {
            logger.info("changing profile from id \(currentlyIdentifiedProfileIdentifier) to \(identifier)")

            logger
                .debug(
                    "deleting token from previously identified profile to prevent sending messages to it. It's assumed that for privacy and messaging relevance, you only want to send messages to devices that a profile is currently identifed with."
                )
            deleteDeviceToken()

            logger.debug("running hooks changing profile from \(currentlyIdentifiedProfileIdentifier) to \(identifier)")
            hooks.profileIdentifyHooks.forEach { hook in
                hook.beforeIdentifiedProfileChange(
                    oldIdentifier: currentlyIdentifiedProfileIdentifier,
                    newIdentifier: identifier
                )
            }
        }

        logger.debug("storing identifier on device storage \(identifier)")
        profileStore.identifier = identifier

        if isFirstTimeIdentifying || isChangingIdentifiedProfile {
            if let existingDeviceToken = globalDataStore.pushDeviceToken {
                logger.debug("registering existing device token to newly identified profile: \(identifier)")
                // this code assumes that the newly identified profile has been saved to device storage. only call this
                // function until after the SDK stores the new profile identifier
                registerDeviceToken(existingDeviceToken)
            }

            logger.debug("running hooks profile identified \(identifier)")
            hooks.profileIdentifyHooks.forEach { hook in
                hook.profileIdentified(identifier: identifier)
            }
        }
    }

    public func clearIdentify() {
        logger.info("clearing identified profile")

        DataPipeline.shared.clearIdentify()

        guard let currentlyIdentifiedProfileIdentifier = profileStore.identifier else {
            return
        }

        logger
            .debug(
                "delete device token from \(currentlyIdentifiedProfileIdentifier) to stop sending push to a profile that is no longer identified"
            )
        deleteDeviceToken()

        logger.debug("running hooks: profile stopped being identified \(currentlyIdentifiedProfileIdentifier)")
        hooks.profileIdentifyHooks.forEach { hook in
            hook.beforeProfileStoppedBeingIdentified(oldIdentifier: currentlyIdentifiedProfileIdentifier)
        }

        logger.debug("deleting profile info from device storage")
        // remove device identifier from storage last so hooks can succeed.
        profileStore.identifier = nil
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
        addDeviceAttributes(deviceToken: deviceToken)
    }

    /**
     Adds device default and custom attributes and registers device token.
     */
    // TODO: Segment doesn't provide this method by default needs to get added
    private func addDeviceAttributes(deviceToken: String, customAttributes: [String: Any] = [:]) {
        // TODO: add support for device attributes in DataPipeline
        DataPipeline.shared.registerDeviceToken(deviceToken)

        logger.info("registering device token \(deviceToken)")
        logger.debug("storing device token to device storage \(deviceToken)")
        // no matter what, save the device token for use later. if a customer is identified later,
        // we can reference the token and register it to a new profile.
        globalDataStore.pushDeviceToken = deviceToken

        guard let identifier = profileStore.identifier else {
            logger.info("no profile identified, so not registering device token to a profile")
            return
        }
        if identifier.isBlankOrEmpty() {
            logger.error("profile cannot be identified: Identifier is empty, so not registering device token to a profile")
            return
        }

        // OS name might not be available if running on non-apple product. We currently only support iOS for the SDK
        // and iOS should always be non-nil. Though, we are consolidating all Apple platforms under iOS but this check
        // is
        // required to prevent SDK execution for unsupported OS.
        if deviceInfo.osName == nil {
            logger.info("SDK being executed from unsupported OS. Ignoring request to register push token.")
            return
        }
        // Consolidate all Apple platforms under iOS
        let deviceOsName = "iOS"
        deviceAttributesProvider.getDefaultDeviceAttributes { defaultDeviceAttributes in
            let deviceAttributes = defaultDeviceAttributes.mergeWith(customAttributes)

            let encodableBody = StringAnyEncodable(logger: self.logger, deviceAttributes) // makes [String: Any] Encodable to use in JSON body.
            let requestBody = RegisterDeviceRequest(device: Device(
                token: deviceToken,
                platform: deviceOsName,
                lastUsed: self.dateUtil.now,
                attributes: encodableBody
            ))

            guard let jsonBodyString = self.jsonAdapter.toJsonString(requestBody) else {
                return
            }
            let queueTaskData = RegisterPushNotificationQueueTaskData(
                profileIdentifier: identifier,
                attributesJsonString: jsonBodyString
            )

            _ = self.backgroundQueue.addTask(
                type: QueueTaskType.registerPushToken.rawValue,
                data: queueTaskData,
                groupStart: .registeredPushToken(token: deviceToken),
                blockingGroups: [.identifiedProfile(identifier: identifier)]
            )
        }
    }

    /**
     Delete the currently registered device token
     */
    // TODO: Segment doesn't provide this method by default needs to get added
    public func deleteDeviceToken() {
        logger.info("deleting device token request made")

        DataPipeline.shared.deleteDeviceToken()

        guard let existingDeviceToken = globalDataStore.pushDeviceToken else {
            logger.info("no device token exists so ignoring request to delete")
            return // no device token to delete, ignore request
        }
        // Do not delete push token from device storage. The token is valid
        // once given to SDK. We need it for future profile identifications.

        guard let identifiedProfileId = profileStore.identifier else {
            logger.info("no profile identified so not removing device token from profile")
            return // no profile to delete token from, ignore request
        }

        _ = backgroundQueue.addTask(
            type: QueueTaskType.deletePushToken.rawValue,
            data: DeletePushNotificationQueueTaskData(
                profileIdentifier: identifiedProfileId,
                deviceToken: existingDeviceToken
            ),
            blockingGroups: [
                .registeredPushToken(token: existingDeviceToken),
                .identifiedProfile(identifier: identifiedProfileId)
            ]
        )
    }

    /**
     Track a push metric
     */
    public func trackMetric(
        deliveryID: String,
        event: Metric,
        deviceToken: String
    ) {
        logger.info("push metric \(event.rawValue)")

        logger.debug("delivery id \(deliveryID) device token \(deviceToken)")

        DataPipeline.shared.trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken)

        _ = backgroundQueue.addTask(
            type: QueueTaskType.trackPushMetric.rawValue,
            data: MetricRequest(
                deliveryId: deliveryID,
                event: event,
                deviceToken: deviceToken,
                timestamp: Date()
            )
        )
    }

    func getAllStoredTasks() -> [QueueTaskMetadata]? {
        backgroundQueue.getAllStoredTasks()
    }

    // TODO: Pending: Clean this method + device attributes + clean individual way to delete processed tasks
    func getStoredTask(for task: QueueTaskMetadata) {
        guard let taskDetail = backgroundQueue.getTaskDetail(task) else { return }
        let taskData = taskDetail.data

        switch taskDetail.taskType {
        case .trackDeliveryMetric:
            // TODO: Segment doesn't provide this method by default needs to get added
            print("Track Delivery Metrics for in-app - Needs discussion/help")
        case .identifyProfile:
            guard let trackTaskData: IdentifyProfileQueueTaskData = jsonAdapter.fromJson(taskData) else {
                return
            }
            guard let profileAttributes: [String: Any] = jsonAdapter.fromJsonString(trackTaskData.attributesJsonString!) else { return }
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
            guard let device = deviceAttributes["device"] as? [String: Any], let token = device["id"] as? String else { return }
            registerDeviceToken(token)
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
