import CioAnalytics
import CioInternalCommon

class DataPipelineImplementation: DataPipelineInstance {
    private let moduleConfig: DataPipelineConfigOptions
    private let logger: Logger
    private let dataPipelinesLogger: DataPipelinesLogger
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
        self.dataPipelinesLogger = diGraph.dataPipelinesLogger
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

        // Add plugin to filter events based on SDK configuration
        analytics.add(plugin: ScreenFilterPlugin(screenViewUse: moduleConfig.screenViewUse))

        // subscribe to journey events emmitted from push/in-app module to send them via datapipelines
        subscribeToJourneyEvents()
        postProfileAlreadyIdentified()
    }

    private func postProfileAlreadyIdentified() {
        if let siteId = moduleConfig.migrationSiteId, let identifier = profileStore.getProfileId(siteId: siteId) {
            eventBusHandler.postEvent(ProfileIdentifiedEvent(identifier: identifier))
        } else if let identifier = analytics.userId {
            eventBusHandler.postEvent(ProfileIdentifiedEvent(identifier: identifier))
        } else if !analytics.anonymousId.isEmpty {
            eventBusHandler.postEvent(AnonymousProfileIdentifiedEvent(identifier: analytics.anonymousId))
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

        eventBusHandler.addObserver(TrackLocationEvent.self) { event in
            self.trackLocation(event)
        }
    }

    private func trackLocation(_ event: TrackLocationEvent) {
        guard let userId = analytics.userId, !userId.isEmpty else { return }
        let location = event.location
        let properties: [String: Any] = ["lat": location.latitude, "lng": location.longitude]
        analytics.track(name: DataPipelineReservedNames.reservedLocationTrackEventName, properties: properties)
        eventBusHandler.postEvent(LocationTrackedEvent(location: location, timestamp: dateUtil.now))
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
    func identify(traits: Codable) {
        if let filtered = codableToDictRemovingReservedLocationKeys(traits), let jsonTraits = try? JSON(filtered) {
            analytics.identify(traits: jsonTraits)
        } else {
            analytics.identify(traits: traits)
        }
    }

    var registeredDeviceToken: String? {
        globalDataStore.pushDeviceToken
    }

    func clearIdentify() {
        logger.info("clearing identified profile")
        commonClearIdentify()
    }

    func track(name: String, properties: [String: Any]?) {
        let (shouldSend, filtered) = filterTrackParameters(name: name, properties: properties)
        guard shouldSend else {
            logger.debug("Ignoring track call for reserved event \"\(DataPipelineReservedNames.reservedLocationTrackEventName)\". Use CustomerIO.location to update location.")
            return
        }
        analytics.track(name: name, properties: filtered)
    }

    func track<RequestBody: Codable>(name: String, properties: RequestBody?) {
        guard !isReservedTrackEventName(name) else {
            logger.debug("Ignoring track call for reserved event \"\(DataPipelineReservedNames.reservedLocationTrackEventName)\". Use CustomerIO.location to update location.")
            return
        }
        if let properties = properties {
            if let filtered = codableToDictRemovingReservedLocationKeys(properties) {
                analytics.track(name: name, properties: filtered)
            } else {
                analytics.track(name: name, properties: properties)
            }
        } else {
            analytics.track(name: name, properties: nil)
        }
    }

    func screen(title: String, properties: [String: Any]?) {
        analytics.screen(title: title, properties: properties)
    }

    func screen<RequestBody: Codable>(title: String, properties: RequestBody?) {
        analytics.screen(title: title, properties: properties)
    }

    @available(*, deprecated, message: "Use setProfileAttributes() instead")
    var profileAttributes: [String: Any] {
        get { analytics.traits() ?? [:] }
        set { setProfileAttributes(newValue) }
    }

    func setProfileAttributes(_ attributes: [String: Any]) {
        let filtered = attributesByRemovingReservedLocationKeys(attributes)
        let userId = registeredUserId
        guard let userId = userId else {
            if let jsonTraits = try? JSON(filtered) {
                analytics.identify(traits: jsonTraits)
            } else {
                logger.error("Failed to convert attributes to JSON format for identify call")
            }
            return
        }
        commonIdentifyProfile(userId: userId, attributesDict: filtered)
    }

    func commonIdentifyProfile(userId: String, attributesDict: [String: Any]? = nil, attributesCodable: Codable? = nil) {
        if userId.isBlankOrEmpty() {
            logger.error("profile cannot be identified: Identifier is empty. Please retry with a valid, non-empty identifier.")
            return
        }
        let currentlyIdentifiedProfile = registeredUserId
        let isChangingIdentifiedProfile = currentlyIdentifiedProfile != nil && currentlyIdentifiedProfile != userId
        let isFirstTimeIdentifying = currentlyIdentifiedProfile == nil
        if isChangingIdentifiedProfile, let _ = registeredDeviceToken {
            dataPipelinesLogger.logDeletingTokenDueToNewProfileIdentification()
            deleteDeviceToken()
        }
        if let attributes = attributesCodable {
            if let filtered = codableToDictRemovingReservedLocationKeys(attributes), let jsonTraits = try? JSON(filtered) {
                analytics.identify(userId: userId, traits: jsonTraits)
            } else {
                analytics.identify(userId: userId, traits: attributes)
            }
        } else {
            let filtered = attributesDict.map { attributesByRemovingReservedLocationKeys($0) }
            analytics.identify(userId: userId, traits: filtered)
        }
        if isFirstTimeIdentifying || isChangingIdentifiedProfile {
            if let existingDeviceToken = registeredDeviceToken {
                dataPipelinesLogger.automaticTokenRegistrationForNewProfile(token: existingDeviceToken, userId: userId)
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

    @available(*, deprecated, message: "Use setDeviceAttributes method instead. This property getter always returns an empty dictionary.")
    var deviceAttributes: [String: Any] {
        get { [:] }
        set {
            setDeviceAttributes(newValue)
        }
    }

    func setDeviceAttributes(_ attributes: [String: Any]) {
        logger.info("updating device attributes")
        addDeviceAttributes(token: contextPlugin.deviceToken, attributes: attributes)
    }

    /// Internal method for passing device token to the plugin and updating device attributes
    private func addDeviceAttributes(token deviceToken: String?, attributes customAttributes: [String: Any] = [:]) {
        guard let token = deviceToken, !token.isBlankOrEmpty() else {
            dataPipelinesLogger.logTrackingDevicesAttributesWithoutValidToken()
            return
        }

        if let existingDeviceToken = contextPlugin.deviceToken, existingDeviceToken != deviceToken {
            // token has been refreshed, delete old token to avoid registering same device multiple times
            dataPipelinesLogger.logPushTokenRefreshed()
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
        if deviceToken.isBlankOrEmpty() {
            dataPipelinesLogger.logStoringBlankPushToken()
            return
        }
        dataPipelinesLogger.logStoringDevicePushToken(token: deviceToken, userId: registeredUserId)
        // save the device token for later use.
        // segment plugin doesn't store token anywhere so we need to pass token to it every time
        // storing it so we can reference the token and update device plugin app relaunch
        globalDataStore.pushDeviceToken = deviceToken

        dataPipelinesLogger.logRegisteringPushToken(token: deviceToken, userId: registeredUserId)
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
