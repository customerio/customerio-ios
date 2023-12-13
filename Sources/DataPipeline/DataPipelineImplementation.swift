import CioInternalCommon
import Segment

class DataPipelineImplementation: DataPipelineInstance {
    private let moduleConfig: DataPipelineConfigOptions
    private let logger: Logger
    let analytics: Analytics

    private var globalDataStore: GlobalDataStore
    private let deviceAttributesProvider: DeviceAttributesProvider
    private let dateUtil: DateUtil
    private let deviceInfo: DeviceInfo

    init(diGraph: DIGraphShared, moduleConfig: DataPipelineConfigOptions) {
        self.moduleConfig = moduleConfig
        self.logger = diGraph.logger
        self.analytics = .init(configuration: moduleConfig.toSegmentConfiguration())

        self.globalDataStore = diGraph.globalDataStore
        self.deviceAttributesProvider = diGraph.deviceAttributesProvider
        self.dateUtil = diGraph.dateUtil
        self.deviceInfo = diGraph.deviceInfo

        initialize()
    }

    private func initialize() {
        if let token = globalDataStore.pushDeviceToken {
            // if the device token exists, pass it to the plugin to ensure device attributes are updated with each request
            setDeviceToken(token)
        }
    }

    // Code below this line will be updated in later PRs
    // FIXME: [CDP] Implement CustomerIOInstance

    var siteId: String?

    var config: CioInternalCommon.SdkConfig?

    func identify(identifier: String, body: [String: Any]) {
        commonIdentifyProfile(userId: identifier, attributesDict: body)
    }

    func identify<RequestBody: Codable>(identifier: String, body: RequestBody) {
        commonIdentifyProfile(userId: identifier, attributesCodable: body)
    }

    var registeredDeviceToken: String? {
        analytics.find(pluginType: DeviceAttributes.self)?.token
    }

    func clearIdentify() {
        // TODO: [CDP] CustomerIOImplementation also call deleteDeviceToken from clearIdentify, but customers using DataPipeline only,
        // we had to call this explicitly. Rethink on how can we make one call for both customers.
        removeDevicePlugin()
        logger.info("clearing identified profile")

        guard let currentlyIdentifiedProfile = analytics.userId else {
            analytics.reset()
            return
        }

        logger.debug("delete device token from \(currentlyIdentifiedProfile) to stop sending push to a profile that is no longer identified")
        removeDevicePlugins()

        logger.debug("running hooks: profile stopped being identified \(currentlyIdentifiedProfile)")
        // FIXME: [CDP] Request Journeys to invoke profile clearing hooks
        // hooks.profileIdentifyHooks.forEach { hook in
        //     hook.beforeProfileStoppedBeingIdentified(oldIdentifier: currentlyIdentifiedProfileIdentifier)
        // }

        logger.debug("resetting user profile")
        // remove device identifier from storage last so hooks can succeed.
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

    var profileAttributes: [String: Any] {
        get { analytics.traits() ?? [:] }
        set {
            let userId = analytics.userId
            guard let userId = userId, userId.isBlankOrEmpty() else {
                logger.error("No user identified: Identifier is null or empty. If you don't have a userId but want to record traits, just pass traits into the event and they will be associated with the anonymousId of that user.")
                return
            }
            commonIdentifyProfile(userId: userId, attributesDict: newValue)
        }
    }

    private func commonIdentifyProfile(userId: String, attributesDict: [String: Any]? = nil, attributesCodable: Codable? = nil) {
        if userId.isBlankOrEmpty() {
            logger.error("profile cannot be identified: Identifier is empty. Please retry with a valid, non-empty identifier.")
            return
        }
        
        let currentlyIdentifiedProfile = analytics.userId
        let isChangingIdentifiedProfile = currentlyIdentifiedProfile != nil && currentlyIdentifiedProfile != userId
        let isFirstTimeIdentifying = currentlyIdentifiedProfile == nil
        
        if let currentlyIdentifiedProfile = currentlyIdentifiedProfile, isChangingIdentifiedProfile {
            logger.info("changing profile from id \(currentlyIdentifiedProfile) to \(userId)")
            
            logger.debug("deleting token from previously identified profile to prevent sending messages to it. It's assumed that for privacy and messaging relevance, you only want to send messages to devices that a profile is currently identifed with.")
            logger.debug("deleting token from previously identified profile to prevent sending messages to it. It's assumed that for privacy and messaging relevance, you only want to send messages to devices that a profile is currently identifed with.")
            deleteDeviceToken()
            
            logger.debug("running hooks changing profile from \(currentlyIdentifiedProfile) to \(userId)")
            // FIXME: [CDP] Request Journeys to invoke profile changing hooks
            // hooks.profileIdentifyHooks.forEach { hook in
            //     hook.beforeIdentifiedProfileChange(
            //         oldIdentifier: currentlyIdentifiedProfile,
            //         newIdentifier: userId
            //     )
            // }
        }
        
        if isFirstTimeIdentifying || isChangingIdentifiedProfile {
            if let existingDeviceToken = globalDataStore.pushDeviceToken {
                logger.debug("registering existing device token to newly identified profile: \(userId)")
                // this code assumes that the newly identified profile has been saved to device storage. only call this
                // function until after the SDK stores the new profile identifier
                registerDeviceToken(existingDeviceToken)
            }
            
            logger.debug("running hooks profile identified \(userId)")
            // FIXME: [CDP] Request Journeys to invoke profile identify hooks
            // hooks.profileIdentifyHooks.forEach { hook in
            //     hook.profileIdentified(identifier: userId)
            // }
        }
        if let attributes = attributesCodable {
            analytics.identify(userId: userId, traits: attributes)
        } else {
            analytics.identify(userId: userId, traits: attributesDict)
        }
    }

    var deviceAttributes: [String: Any] {
        get {
            let attributesPlugin = analytics.find(pluginType: DeviceAttributes.self)
            return attributesPlugin?.attributes ?? [:]
        }
        set {
            let attributesPlugin = analytics.find(pluginType: DeviceAttributes.self)
            addDeviceAttributes(token: attributesPlugin?.token, attributes: newValue)
        }
    }

    /// Adds device default and custom attributes using DeviceAttributes plugin
    private func addDeviceAttributes(token deviceToken: String? = nil, attributes customAttributes: [String: Any] = [:]) {
        // Consolidate all Apple platforms under iOS
        let deviceOsName = "iOS"
        deviceAttributesProvider.getDefaultDeviceAttributes { defaultDeviceAttributes in
            let deviceAttributes: [String: Any] = defaultDeviceAttributes
                .mergeWith([
                    "platform": deviceOsName,
                    "lastUsed": self.dateUtil.now
                ])
                .mergeWith(customAttributes)

            // Make sure DeviceAttributes plugin is attached
            let attributesPlugin: DeviceAttributes
            if let plugin = self.analytics.find(pluginType: DeviceAttributes.self) {
                attributesPlugin = plugin
            } else {
                attributesPlugin = DeviceAttributes()
                self.analytics.add(plugin: attributesPlugin)
            }

            attributesPlugin.attributes = deviceAttributes
            attributesPlugin.token = deviceToken
        }
    }

    func registerDeviceToken(_ deviceToken: String) {
        logger.debug("storing device token to device storage \(deviceToken)")
        // save the device token for later use.
        // segment plugin doesn't store token anywhere so we need to pass token to it every time
        // storing it so we can reference the token and register on app relaunch
        globalDataStore.pushDeviceToken = deviceToken
        setDeviceToken(deviceToken)
    }

    /// Internal method for passing the device token to the plugin
    private func setDeviceToken(_ deviceToken: String) {
        logger.info("registering device token \(deviceToken)")

        addDeviceAttributes(token: deviceToken)
    }

    func deleteDeviceToken() {
        logger.info("deleting device token request made")

        // Do not delete push token from device storage. The token is valid
        // once given to SDK. We need it for future profile identifications.

        removeDevicePlugin()
    }

    /// Internal method for removing attached plugins to stop sending device token and attributes
    private func removeDevicePlugin() {
        // Remove DeviceAttributes plugin to avoid attaching token and attributes to every request.
        if let attributesPlugin = analytics.find(pluginType: DeviceAttributes.self) {
            analytics.remove(plugin: attributesPlugin)
            logger.info("DeviceAttributes plugin removed")
        }
    }

    func trackMetric(deliveryID: String, event: Metric, deviceToken: String) {
        // FIXME: [CDP] Update name to match the expectation
        let name = "Push Metric"
        let properties = MetricEvent(event: name, metric: event, deliveryId: deliveryID, deliveryToken: deviceToken)
        analytics.track(name: name, properties: properties)
    }
}
