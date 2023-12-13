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
        get { DataPipeline.shared.deviceAttributes }
        set { DataPipeline.shared.deviceAttributes = newValue }
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
        logger.info("initiating device token registration for \(deviceToken)")
        // if the request is not forwarded to DataPipeline, make sure to save the device token for later use.
        // so if a customer is identified later, we can reference the token and register it to a new profile.

        guard let identifier = DataPipeline.shared.analytics.userId else {
            logger.debug("storing device token to device storage \(deviceToken)")
            globalDataStore.pushDeviceToken = deviceToken

            logger.info("no profile identified, so not registering device token to a profile")
            return
        }
        if identifier.isBlankOrEmpty() {
            logger.debug("storing device token to device storage \(deviceToken)")
            globalDataStore.pushDeviceToken = deviceToken

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
        DataPipeline.shared.registerDeviceToken(deviceToken)
    }

    /**
     Delete the currently registered device token
     */
    // TODO: Segment doesn't provide this method by default needs to get added
    public func deleteDeviceToken() {
        logger.info("initiating request to delete device token")

        guard (globalDataStore.pushDeviceToken) != nil else {
            logger.info("no device token exists so ignoring request to delete")
            return // no device token to delete, ignore request
        }
        // Do not delete push token from device storage. The token is valid
        // once given to SDK. We need it for future profile identifications.

        guard (DataPipeline.shared.analytics.userId) != nil else {
            logger.info("no profile identified so not removing device token from profile")
            return // no profile to delete token from, ignore request
        }

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
}
