import CioAnalytics
import CioInternalCommon

class DataPipelineImplementation: DataPipelineInstance, DataPipelineTracking, BackgroundDeliveryCdpApiKeyProvider {
    let moduleConfig: DataPipelineConfigOptions
    private let logger: Logger
    private let dataPipelinesLogger: DataPipelinesLogger
    let analytics: Analytics
    /// Every event and identity read goes through here, never `analytics` directly.
    let segment: SegmentGateway
    let eventBusHandler: EventBusHandler

    private var globalDataStore: GlobalDataStore
    let deviceTokenLock = Lock.unsafeInit()
    private let deviceAttributesProvider: DeviceAttributesProvider
    private let dateUtil: DateUtil
    let deviceInfo: DeviceInfo
    let contextPlugin: Context
    private let profileStore: ProfileStore
    private let backgroundDeliveryContextStore: BackgroundDeliveryContextStore

    /// Per-session tracker of the most recently identified userId. Used to dedup
    /// no-traits identify calls against the same userId within a single process
    /// lifetime. Reset by `clearIdentify()`. Not persisted across launches so
    /// that the first identify per cold-start always runs the full path
    /// (device-token re-registration + DCoU refresh).
    private var lastIdentifiedUserIdThisSession: String?

    init(diGraph: DIGraphShared, moduleConfig: DataPipelineConfigOptions) {
        self.moduleConfig = moduleConfig
        self.logger = diGraph.logger
        self.dataPipelinesLogger = diGraph.dataPipelinesLogger
        // Keep identity and queued events when the app switches to a `pk_` key.
        AnalyticsStorageMigration.run(for: moduleConfig.cdpApiKey, diGraph: diGraph)
        self.analytics = diGraph.segmentFactory.makeAnalytics(moduleConfig.toSegmentConfiguration())

        self.eventBusHandler = diGraph.eventBusHandler
        self.globalDataStore = diGraph.globalDataStore
        self.deviceAttributesProvider = diGraph.deviceAttributesProvider
        self.dateUtil = diGraph.dateUtil
        self.deviceInfo = diGraph.deviceInfo
        self.profileStore = diGraph.profileStore
        self.backgroundDeliveryContextStore = diGraph.backgroundDeliveryContextStore

        self.contextPlugin = Context(diGraph: diGraph)
        self.segment = diGraph.segmentFactory.makeGateway(analytics)

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

        // plugin that adds provider attributes (e.g. location) to identify context
        analytics.add(plugin: IdentifyContextPlugin(registry: diGraph.profileEnrichmentRegistry, logger: logger))

        // plugin to publish data pipeline events
        analytics.add(plugin: DataPipelinePublishedEvents(diGraph: diGraph))

        // Add plugin to filter events based on SDK configuration
        analytics.add(plugin: ScreenFilterPlugin(screenViewUse: moduleConfig.screenViewUse))

        // Register as DataPipelineTracking so modules (e.g. Location) can send track events via getOptional
        diGraph.register(self, forType: DataPipelineTracking.self)

        // Persisted so cold-wake background-delivery callers can route requests without
        // requiring DataPipeline to be initialized in their process.
        backgroundDeliveryContextStore.setApiHost(moduleConfig.apiHost)

        // cdpApiKey is only persisted when the customer explicitly opts in. Clearing on
        // opt-out wipes any key left by a prior launch that had it enabled.
        if moduleConfig.allowBackgroundDelivery {
            backgroundDeliveryContextStore.setCdpApiKey(moduleConfig.cdpApiKey)
        } else {
            backgroundDeliveryContextStore.setCdpApiKey(nil)
        }

        // Live provider for foreground real-time delivery — `currentCdpApiKey` returns the
        // in-memory key even when `allowBackgroundDelivery` is off (no disk persistence).
        backgroundDeliveryContextStore.setCdpApiKeyProvider(self)

        // subscribe to journey events emmitted from push/in-app module to send them via datapipelines
        subscribeToJourneyEvents()
        postProfileAlreadyIdentified()
    }

    private func postProfileAlreadyIdentified() {
        if let siteId = moduleConfig.migrationSiteId, let identifier = profileStore.getProfileId(siteId: siteId) {
            backgroundDeliveryContextStore.setUserId(identifier)
            eventBusHandler.postEvent(ProfileIdentifiedEvent(identifier: identifier))
        } else if let identifier = segment.userId {
            backgroundDeliveryContextStore.setUserId(identifier)
            eventBusHandler.postEvent(ProfileIdentifiedEvent(identifier: identifier))
        } else if !segment.anonymousId.isEmpty {
            eventBusHandler.postEvent(AnonymousProfileIdentifiedEvent(identifier: segment.anonymousId))
        }
    }

    private func subscribeToJourneyEvents() {
        // Each bus event is an input of its own (`DataPipelineLogTail`), logged when the SDK handles it
        eventBusHandler.addObserver(TrackMetricEvent.self) { metric in
            DataPipelineLogTail.input("bus.push_metric", [("metric", metric.event), ("delivery", metric.deliveryID)]) { self.trackPushMetric(deliveryID: metric.deliveryID, event: metric.event, deviceToken: metric.deviceToken) }
        }

        eventBusHandler.addObserver(TrackInAppMetricEvent.self) { metric in
            DataPipelineLogTail.input("bus.inapp_metric", [("metric", metric.event), ("delivery", metric.deliveryID)]) { self.trackInAppMetric(deliveryID: metric.deliveryID, event: metric.event, metaData: metric.params) }
        }

        eventBusHandler.addObserver(TrackGeofenceMetricEvent.self) { metric in
            DataPipelineLogTail.input("bus.geofence_transition", [("event", metric.trackEventName)]) { self.processGeofenceMetricEvent(metric) }
        }

        eventBusHandler.addObserver(RegisterDeviceTokenEvent.self) { event in
            DataPipelineLogTail.input("bus.register_token", [("token", event.token)]) {
                // Events are delivered concurrently, and the same token can be posted again before it's stored
                self.deviceTokenLock.lock()
                defer { self.deviceTokenLock.unlock() }
                guard !self.globalDataStore.isPushDeviceTokenStored(event.token, type: event.tokenType) else { return }
                self.registerDeviceToken(event.token, tokenType: event.tokenType)
            }
        }
    }

    // MARK: - BackgroundDeliveryCdpApiKeyProvider

    var cdpApiKey: String? {
        moduleConfig.cdpApiKey
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
        segment.identify(traits: traits)
    }

    var registeredDeviceToken: String? {
        globalDataStore.pushDeviceToken
    }

    func clearIdentify() {
        logger.info("clearing identified profile")
        commonClearIdentify()
    }

    func track(name: String, properties: [String: Any]?) {
        segment.track(name: name, properties: properties)
    }

    func track<RequestBody: Codable>(name: String, properties: RequestBody?) {
        segment.track(name: name, properties: properties)
    }

    func screen(title: String, properties: [String: Any]?) {
        segment.screen(title: title, category: nil, properties: properties)
    }

    func screen<RequestBody: Codable>(title: String, properties: RequestBody?) {
        segment.screen(title: title, category: nil, properties: properties)
    }

    func setProfileAttributes(_ attributes: [String: Any]) {
        let userId = registeredUserId
        guard let userId = userId else {
            if let jsonTraits = try? JSON(attributes) {
                segment.identify(traits: jsonTraits)
            } else {
                logger.error("Failed to convert attributes to JSON format for identify call")
            }
            return
        }
        commonIdentifyProfile(userId: userId, attributesDict: attributes)
    }

    func commonIdentifyProfile(userId: String, attributesDict: [String: Any]? = nil, attributesCodable: Codable? = nil) {
        if userId.isBlankOrEmpty() {
            logger.error("profile cannot be identified: Identifier is empty. Please retry with a valid, non-empty identifier.")
            return
        }

        // Per-session dedup: short-circuit when this exact userId was already
        // identified during this process lifetime AND no traits are supplied.
        // An explicit empty dict (`[:]`) is treated as "traits supplied" and
        // passes through, because some integrations rely on the empty-traits
        // identify call as an intentional no-op trait merge.
        let hasNoTraits = attributesDict == nil && attributesCodable == nil
        if hasNoTraits, let lastUserId = lastIdentifiedUserIdThisSession, lastUserId == userId {
            logger.debug("identify(\(userId)) skipped — already identified this session, no traits")
            return
        }

        let currentlyIdentifiedProfile = registeredUserId
        let isChangingIdentifiedProfile = currentlyIdentifiedProfile != nil && currentlyIdentifiedProfile != userId
        let isFirstTimeIdentifying = currentlyIdentifiedProfile == nil

        if isChangingIdentifiedProfile, let _ = registeredDeviceToken {
            dataPipelinesLogger.logDeletingTokenDueToNewProfileIdentification()
            deleteDeviceToken()
        }

        // Mirror for cold-wake direct-HTTP callers. Must precede `segment.identify`, which
        // publishes `ProfileIdentifiedEvent` from a `.before` plugin — subscribers resolve the
        // user from this store, and would otherwise read nil.
        backgroundDeliveryContextStore.setUserId(userId)

        if let attributes = attributesCodable {
            segment.identify(userId: userId, traits: attributes)
        } else {
            segment.identify(userId: userId, traits: attributesDict)
        }

        // Update session tracker so subsequent no-traits same-userId calls
        // within this session can dedup. Identify-with-traits passes through
        // but still refreshes the session tracker.
        lastIdentifiedUserIdThisSession = userId

        if isFirstTimeIdentifying || isChangingIdentifiedProfile {
            if let existingDeviceToken = registeredDeviceToken {
                dataPipelinesLogger.automaticTokenRegistrationForNewProfile(token: existingDeviceToken, userId: userId)
                // register device to newly identified profile
                addDeviceAttributes(token: existingDeviceToken)
            }
        }
    }

    private func commonClearIdentify() {
        let currentlyIdentifiedProfile = registeredUserId ?? "anonymous"
        logger.debug("deleting device info from \(currentlyIdentifiedProfile) to stop sending push to a profile that is no longer identified")
        deleteDeviceToken()
        backgroundDeliveryContextStore.clearUserId()

        // reset all to default state
        logger.debug("resetting user profile")
        segment.reset()

        // Reset per-session identify dedup tracker so the next identify (even
        // for the same userId) takes the full path.
        lastIdentifiedUserIdThisSession = nil
    }

    func deleteDeviceToken() {
        logger.info("deleting device token request made")

        // Do not delete push token from device storage. The token is valid
        // once given to SDK. We need it for future profile identifications.

        if let storedToken = registeredDeviceToken {
            // send delete device event to remove it from current profile only if the token was registered before
            // The Context plugin adds the token when the event is processed, which can be after a newer token is
            // set (events wait while settings refresh). Set the token being deleted on the event.
            let token = contextPlugin.deviceToken ?? storedToken
            segment.track(name: "Device Deleted", properties: nil, deviceToken: token)
            forgetSentPushEnabled()
        }
    }

    func setDeviceAttributes(_ attributes: [String: Any]) {
        logger.info("updating device attributes")
        addDeviceAttributes(token: contextPlugin.deviceToken, attributes: attributes)
    }

    /// Internal method for passing device token to the plugin and updating device attributes
    func addDeviceAttributes(token deviceToken: String?, attributes customAttributes: [String: Any] = [:]) {
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

        // The answer can come after later inputs; its hand-off still belongs to this one
        let call = DataPipelineLogTail.currentCall
        // Consolidate all Apple platforms under iOS
        deviceAttributesProvider.getDefaultDeviceAttributes { defaultDeviceAttributes in
            // A token registered since then sends its own events. Tracking this one late would re-create the device just deleted.
            // Registration holds this lock, so the token can't change between this check and tracking.
            self.deviceTokenLock.lock()
            defer { self.deviceTokenLock.unlock() }
            guard self.contextPlugin.deviceToken == token else {
                self.logger.debug("device token changed or removed, ignoring device attributes request")
                return
            }

            // Read here, as the same token can get a type while attributes load.
            // Sent even when automatic device attributes are off, as the backend uses it to tell FIDs from tokens.
            let tokenType = self.globalDataStore.pushDeviceToken == token ? self.globalDataStore.pushDeviceTokenType : nil
            let deviceAttributes = defaultDeviceAttributes.mergeWith(customAttributes.withDeviceTokenType(tokenType, logger: self.dataPipelinesLogger))
            self.contextPlugin.attributes = deviceAttributes
            // The SDK's value, not a custom one, so the push_enabled refresh keeps a custom value until the permission changes
            self.contextPlugin.attributes[DeviceAttributeKey.pushEnabled] = defaultDeviceAttributes[DeviceAttributeKey.pushEnabled]
            DataPipelineLogTail.running(call) { self.segment.track(name: "Device Created or Updated", properties: deviceAttributes, deviceToken: token) }
        }
    }

    func trackDeliveryEvent(token: String?, event: String, deliveryId: String, timestamp: String) {
        processMetricsFromBGQ(token: token, event: event, deliveryId: deliveryId, timestamp: timestamp, metaData: [:])
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

        segment.track(name: "Report Delivery Event", properties: properties)
    }
}

// MARK: - Device token

extension DataPipelineImplementation {
    func registerDeviceToken(_ deviceToken: String) {
        registerDeviceToken(deviceToken, tokenType: nil)
    }

    func registerDeviceToken(_ deviceToken: String, tokenType: DeviceTokenType?) {
        // Apps can call this directly while the event handler registers a token
        deviceTokenLock.lock()
        defer { deviceTokenLock.unlock() }
        if deviceToken.isBlankOrEmpty() {
            dataPipelinesLogger.logStoringBlankPushToken()
            return
        }
        dataPipelinesLogger.logStoringDevicePushToken(token: deviceToken, userId: registeredUserId)
        // save the device token for later use.
        // segment plugin doesn't store token anywhere so we need to pass token to it every time
        // storing it so we can reference the token and update device plugin app relaunch
        globalDataStore.savePushDeviceToken(deviceToken, type: tokenType)

        dataPipelinesLogger.logRegisteringPushToken(token: deviceToken, userId: registeredUserId)
        addDeviceAttributes(token: deviceToken)
    }
}
