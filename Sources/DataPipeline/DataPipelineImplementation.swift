import CioAnalytics
import CioInternalCommon

class DataPipelineImplementation: DataPipelineInstance {
    private let moduleConfig: DataPipelineConfigOptions
    private let logger: Logger
    let analytics: Analytics
    let eventBusHandler: EventBusHandler

    private var globalDataStore: GlobalDataStore
    private let deviceAttributesProvider: DeviceAttributesProvider
    private let dateUtil: DateUtil
    private let deviceInfo: DeviceInfo
    private let contextPlugin: Context
    private let profileStore: ProfileStore

    init(diGraph: DIGraphShared, moduleConfig: DataPipelineConfigOptions) {
        self.moduleConfig = moduleConfig
        self.logger = diGraph.logger
        self.analytics = .init(configuration: moduleConfig.toSegmentConfiguration())

        self.eventBusHandler = diGraph.eventBusHandler
        self.globalDataStore = diGraph.globalDataStore
        self.deviceAttributesProvider = diGraph.deviceAttributesProvider
        self.dateUtil = diGraph.dateUtil
        self.deviceInfo = diGraph.deviceInfo
        self.profileStore = diGraph.profileStore

        self.contextPlugin = Context(diGraph: diGraph)

        initialize(diGraph: diGraph)
    }

    private func initialize(diGraph: DIGraphShared) {
        // enable Analytics logs accordingly to logLevel
        Analytics.debugLogsEnabled = logger.logLevel == .debug

        // add CustomerIO destination plugin
        if moduleConfig.autoAddCustomerIODestination {
            let customerIODestination = CustomerIODestination()
            customerIODestination.analytics = analytics
            analytics.add(plugin: customerIODestination)
        }

        // plugin to add contextual information to device attributes
        if moduleConfig.autoTrackDeviceAttributes {
            analytics.add(plugin: DeviceContexualAttributes())
        }

        // add configured plugins to analytics
        for plugin in moduleConfig.autoConfiguredPlugins {
            analytics.add(plugin: plugin)
        }

        // plugin to update context properties for each request
        analytics.add(plugin: contextPlugin)

        // plugin to publish data pipeline events
        analytics.add(plugin: DataPipelinePublishedEvents(diGraph: diGraph))

        // subscribe to journey events emmitted from push/in-app module to send them via datapipelines
        subscribeToJourneyEvents()
        postProfileAlreadyIdentified()
    }

    private func postProfileAlreadyIdentified() {
        if let siteId = moduleConfig.migrationSiteId, let identifier = profileStore.getProfileId(siteId: siteId) {
            eventBusHandler.postEvent(ProfileIdentifiedEvent(identifier: identifier))
        } else if let identifier = analytics.userId {
            eventBusHandler.postEvent(ProfileIdentifiedEvent(identifier: identifier))
        }
    }

    private func subscribeToJourneyEvents() {
        eventBusHandler.addObserver(TrackMetricEvent.self) { metric in
            self.trackPushMetric(deliveryID: metric.deliveryID, event: metric.event, deviceToken: metric.deviceToken)
        }

        eventBusHandler.addObserver(TrackInAppMetricEvent.self) { metric in
            self.trackInAppMetric(deliveryID: metric.deliveryID, event: metric.event, metaData: metric.params)
        }

        eventBusHandler.addObserver(RegisterDeviceTokenEvent.self) { event in
            self.registerDeviceToken(event.token)
        }
    }

    var siteId: String?

    var config: CioInternalCommon.SdkConfig?

    func identify(userId: String, traits: [String: Any]?) {
        commonIdentifyProfile(userId: userId, attributesDict: traits)
    }

    func identify<RequestBody: Codable>(userId: String, traits: RequestBody?) {
        commonIdentifyProfile(userId: userId, attributesCodable: traits)
    }

    /// Associate a user with their unique ID and record traits about them.
    /// - Parameters:
    ///   - traits: A dictionary of traits you know about the user. Things like: email, name, plan, etc.
    func identify(traits: Codable) {
        analytics.identify(traits: traits)
    }

    var registeredDeviceToken: String? {
        globalDataStore.pushDeviceToken
    }

    func clearIdentify() {
        logger.info("clearing identified profile")
        commonClearIdentify()
    }

    func track(name: String, properties: [String: Any]?) {
        analytics.track(name: name, properties: properties)
    }

    func track<RequestBody: Codable>(name: String, properties: RequestBody?) {
        analytics.track(name: name, properties: properties)
    }

    func screen(title: String, properties: [String: Any]?) {
        analytics.screen(title: title, properties: properties)
    }

    func screen<RequestBody: Codable>(title: String, properties: RequestBody?) {
        analytics.screen(title: title, properties: properties)
    }

    var profileAttributes: [String: Any] {
        get { analytics.traits() ?? [:] }
        set {
            let userId = registeredUserId
            guard let userId = userId else {
                logger.error("No user identified. If you don't have a userId but want to record traits, please pass traits using identify(body: Codable)")
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

        let currentlyIdentifiedProfile = registeredUserId
        let isChangingIdentifiedProfile = currentlyIdentifiedProfile != nil && currentlyIdentifiedProfile != userId
        let isFirstTimeIdentifying = currentlyIdentifiedProfile == nil

        if isChangingIdentifiedProfile, let _ = registeredDeviceToken {
            logger.debug("deleting registered device token from existing profile: \(currentlyIdentifiedProfile ?? "nil")")
            deleteDeviceToken()
        }

        if let attributes = attributesCodable {
            analytics.identify(userId: userId, traits: attributes)
        } else {
            analytics.identify(userId: userId, traits: attributesDict)
        }

        if isFirstTimeIdentifying || isChangingIdentifiedProfile {
            if let existingDeviceToken = registeredDeviceToken {
                logger.debug("registering existing device token to newly identified profile: \(userId)")
                // register device to newly identified profile
                addDeviceAttributes(token: existingDeviceToken)
            }
        }
    }

    private func commonClearIdentify() {
        let currentlyIdentifiedProfile = registeredUserId ?? "anonymous"
        logger.debug("deleting device info from \(currentlyIdentifiedProfile) to stop sending push to a profile that is no longer identified")
        deleteDeviceToken()

        // reset all to default state
        logger.debug("resetting user profile")
        analytics.reset()
    }

    func deleteDeviceToken() {
        logger.info("deleting device token request made")

        // Do not delete push token from device storage. The token is valid
        // once given to SDK. We need it for future profile identifications.

        if let _ = registeredDeviceToken {
            // send delete device event to remove it from current profile only if the token was registered before
            analytics.track(name: "Device Deleted")
        }
    }

    var deviceAttributes: [String: Any] {
        get { [:] }
        set {
            logger.info("updating device attributes")
            addDeviceAttributes(token: contextPlugin.deviceToken, attributes: newValue)
        }
    }

    /// Internal method for passing device token to the plugin and updating device attributes
    private func addDeviceAttributes(token deviceToken: String?, attributes customAttributes: [String: Any] = [:]) {
        if let existingDeviceToken = contextPlugin.deviceToken, existingDeviceToken != deviceToken {
            // token has been refreshed, delete old token to avoid registering same device multiple times
            deleteDeviceToken()
        }
        contextPlugin.deviceToken = deviceToken

        // Consolidate all Apple platforms under iOS
        deviceAttributesProvider.getDefaultDeviceAttributes { defaultDeviceAttributes in
            let deviceAttributes: [String: Any] = defaultDeviceAttributes.mergeWith(customAttributes)
            self.contextPlugin.attributes = deviceAttributes

            guard self.contextPlugin.deviceToken != nil else {
                self.logger.debug("no device token found, ignoring device attributes request")
                return
            }

            self.analytics.track(name: "Device Created or Updated", properties: deviceAttributes)
        }
    }

    func registerDeviceToken(_ deviceToken: String) {
        logger.debug("storing device token to device storage \(deviceToken)")
        // save the device token for later use.
        // segment plugin doesn't store token anywhere so we need to pass token to it every time
        // storing it so we can reference the token and update device plugin app relaunch
        globalDataStore.pushDeviceToken = deviceToken

        logger.info("registering device token \(deviceToken)")
        addDeviceAttributes(token: deviceToken)
    }

    func trackMetric(deliveryID: String, event: Metric, deviceToken: String) {
        trackPushMetric(deliveryID: deliveryID, event: event.rawValue, deviceToken: deviceToken)
    }

    func trackPushMetric(deliveryID: String, event: String, deviceToken: String) {
        logger.info("push metric \(event)")

        logger.debug("delivery id \(deliveryID) device token \(deviceToken)")

        trackMetricEvent(deliveryID: deliveryID, event: event, deviceToken: deviceToken)
    }

    func trackInAppMetric(deliveryID: String, event: String, metaData: [String: String]) {
        logger.info("in-app metric \(event)")

        logger.debug("delivery id \(deliveryID) metaData \(metaData)")

        trackMetricEvent(deliveryID: deliveryID, event: event, metaData: metaData)
    }

    /// Tracks metric events for push and in-app messages
    private func trackMetricEvent(deliveryID: String, event: String, deviceToken: String? = nil, metaData: [String: String] = [:]) {
        // property keys should be camelCase
        var properties: [String: String] = metaData

        properties["metric"] = event
        properties["deliveryId"] = deliveryID

        if let token = deviceToken {
            properties["recipient"] = token
        }

        analytics.track(name: "Report Delivery Event", properties: properties)
    }
}

// extension methods to simplify and reduce repetitive coding
extension DataPipelineImplementation {
    /// returns user id for currently identifier profile
    var registeredUserId: String? {
        analytics.userId
    }
}

// To process pending tasks in background queue
// BGQ in each of the following methods refer to background queue
extension DataPipelineImplementation {
    func processAlreadyIdentifiedUser(identifier: String) {
        commonIdentifyProfile(userId: identifier)
    }

    func processIdentifyFromBGQ(identifier: String, timestamp: String, body: [String: Any]?) {
        var identifyEvent = IdentifyEvent(userId: identifier, traits: nil)
        identifyEvent.timestamp = timestamp
        if let traits = body {
            let jsonTraits = try? JSON(traits)
            identifyEvent.traits = jsonTraits
        }
        analytics.process(event: identifyEvent)
    }

    func processScreenEventFromBGQ(identifier: String, name: String, timestamp: String?, properties: [String: Any]) {
        var screenEvent = ScreenEvent(title: name, category: nil)
        screenEvent.userId = identifier
        screenEvent.timestamp = timestamp
        if let jsonProperties = try? JSON(properties) {
            screenEvent.properties = jsonProperties
        }
        analytics.process(event: screenEvent)
    }

    func processEventFromBGQ(identifier: String, name: String, timestamp: String?, properties: [String: Any]) {
        var trackEvent = TrackEvent(event: name, properties: nil)
        trackEvent.userId = identifier
        trackEvent.timestamp = timestamp
        if let jsonProperties = try? JSON(properties) {
            trackEvent.properties = jsonProperties
        }
        analytics.process(event: trackEvent)
    }

    func processDeleteTokenFromBGQ(identifier: String, token: String, timestamp: String) {
        var trackDeleteEvent = TrackEvent(event: "Device Deleted", properties: nil)
        trackDeleteEvent.userId = identifier
        trackDeleteEvent.timestamp = timestamp
        let deviceDict: [String: Any] = ["device": ["token": token, "type": "ios"]]
        if let context = try? JSON(deviceDict) {
            trackDeleteEvent.context = context
        }
        analytics.process(event: trackDeleteEvent)
    }

    func processRegisterDeviceFromBGQ(identifier: String, token: String, timestamp: String, attributes: [String: Any]? = nil) {
        var trackRegisterTokenEvent = TrackEvent(event: "Device Created or Updated", properties: nil)
        trackRegisterTokenEvent.userId = identifier
        trackRegisterTokenEvent.timestamp = timestamp
        let tokenDict: [String: Any] = ["token": token, "type": "ios"]

        let deviceDict: [String: Any] = ["device": tokenDict]
        if let context = try? JSON(deviceDict) {
            trackRegisterTokenEvent.context = context
        }
        if let attributes = attributes, let attributes = try? JSON(attributes) {
            trackRegisterTokenEvent.properties = attributes
        }
        analytics.process(event: trackRegisterTokenEvent)
    }

    func processMetricsFromBGQ(token: String?, event: String, deliveryId: String, timestamp: String, metaData: [String: Any]) {
        var properties: [String: Any] = metaData.mergeWith([
            "metric": event,
            "deliveryId": deliveryId
        ])
        if let token = token {
            properties["recipient"] = token
        }
        var trackPushMetricEvent = TrackEvent(event: "Report Delivery Event", properties: try? JSON(properties))
        // anonymousId or userId is required in the payload for backend processing
        trackPushMetricEvent.anonymousId = deliveryId
        trackPushMetricEvent.timestamp = timestamp
        analytics.process(event: trackPushMetricEvent)
    }
}
