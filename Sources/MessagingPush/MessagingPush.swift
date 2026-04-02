import CioInternalCommon
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/**
 Swift code goes into this module that are common to *all* of the Messaging Push modules (APN, FCM, etc).
 So, performing an HTTP request to the API with a device token goes here.
 */
public class MessagingPush: ModuleTopLevelObject<MessagingPushInstance>, MessagingPushInstance {
    @_spi(Internal) public static var appDelegateIntegratedExplicitly: Bool = false

    @Atomic public private(set) static var shared = MessagingPush()
    @Atomic public private(set) static var moduleConfig: MessagingPushConfigOptions = MessagingPushConfigBuilder().build()

    private static let moduleName = "MessagingPush"

    private var globalDataStore: GlobalDataStore

    // singleton constructor
    private init() {
        self.globalDataStore = DIGraphShared.shared.globalDataStore
        super.init(moduleName: Self.moduleName)
    }

    #if DEBUG
    // Methods to set up the test environment.
    // In unit tests, any implementation of the interface works, while integration tests use the actual implementation.

    @discardableResult
    static func setUpSharedInstanceForUnitTest(implementation: MessagingPushInstance, diGraphShared: DIGraphShared, config: MessagingPushConfigOptions) -> MessagingPushInstance {
        // initialize static properties before implementation creation, as they may be directly used by other classes
        moduleConfig = config
        shared.globalDataStore = diGraphShared.globalDataStore
        shared._implementation = implementation
        return implementation
    }

    @discardableResult
    static func setUpSharedInstanceForIntegrationTest(diGraphShared: DIGraphShared, config: MessagingPushConfigOptions) -> MessagingPushInstance {
        moduleConfig = config
        let implementation = MessagingPushImplementation(diGraph: diGraphShared, moduleConfig: config)
        return setUpSharedInstanceForUnitTest(implementation: implementation, diGraphShared: diGraphShared, config: config)
    }

    static func resetTestEnvironment() {
        moduleConfig = MessagingPushConfigBuilder().build()
        shared = MessagingPush()
    }
    #endif

    /**
     Initialize the shared `instance` of `MessagingPush`.
     Call this function when your app launches, before using `MessagingPush.shared`.
     */
    @discardableResult
    @available(iOSApplicationExtension, unavailable)
    public static func initialize(withConfig config: MessagingPushConfigOptions = MessagingPushConfigBuilder().build()) -> MessagingPushInstance {
        shared.initializeModuleIfNotAlready {
            // set moduleConfig before creating implementation instance as dependencies inside instance may directly use moduleConfig from MessagingPush.
            Self.moduleConfig = config
            // Some part of the initialize is specific only to non-NSE targets.
            // Put those parts in this non-NSE initialize method.
            if config.autoTrackPushEvents, !Self.appDelegateIntegratedExplicitly {
                DIGraphShared.shared.automaticPushClickHandling.start()
            }
            DIGraphShared.shared.registerPendingPushDeliveryStore()
            Self.schedulePendingPushDeliveryMetricsFlush()

            return shared.getImplementation(config: config)
        }

        return shared
    }

    /// MessagingPush initializer for Notification Service Extension
    @available(iOS, unavailable)
    @available(visionOS, unavailable)
    @available(iOSApplicationExtension, introduced: 13.0)
    @available(visionOSApplicationExtension, introduced: 1.0)
    @discardableResult
    public static func initializeForExtension(withConfig config: MessagingPushConfigOptions) -> MessagingPushInstance {
        shared.initializeModuleIfNotAlready {
            // set moduleConfig before creating implementation instance as dependencies inside instance may directly use moduleConfig from MessagingPush.
            Self.moduleConfig = config
            // set logLevel of shared logger only when module is initialized from NotificationServiceExtension.
            DIGraphShared.shared.logger.setLogLevel(config.logLevel)
            DIGraphShared.shared.registerPendingPushDeliveryStore()
            return shared.getImplementation(config: config)
        }

        return shared
    }

    private func getImplementation(config: MessagingPushConfigOptions) -> MessagingPushInstance {
        MessagingPushImplementation(diGraph: DIGraphShared.shared, moduleConfig: config)
    }

    /**
     Register a new device token with Customer.io, associated with the current active customer. If there
     is no active customer, this will fail to register the device
     */
    public func registerDeviceToken(_ deviceToken: String) {
        // Compare the new deviceToken with the one stored in globalDataStore.
        // If they are different, proceed with registering the device token.
        // This check helps to avoid duplicate requests, as registerDeviceToken is already called on SDK initialization.
        if deviceToken != globalDataStore.pushDeviceToken {
            // Call the registerDeviceToken method on the implementation.
            // This method is responsible for registering the device token and updating the globalDataStore as well.
            if let implementation = implementation {
                implementation.registerDeviceToken(deviceToken)
            } else {
                // Update the globalDataStore with the new device token.
                // The implementation may be nil due to lifecycle issues in wrappers SDKs.
                globalDataStore.pushDeviceToken = deviceToken
            }
        }
    }

    /**
     Delete the currently registered device token
     */
    public func deleteDeviceToken() {
        implementation?.deleteDeviceToken()
    }

    /**
     Track a push metric
     */
    public func trackMetric(
        deliveryID: String,
        event: Metric,
        deviceToken: String
    ) {
        implementation?.trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken)
    }

    #if canImport(UserNotifications)
    /**
     - returns:
     Bool indicating if this push notification is one handled by Customer.io SDK or not.
     If function returns `false`, `contentHandler` will *not* be called by the SDK.
     */
    @discardableResult
    public func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) -> Bool {
        guard let implementation = implementation else {
            contentHandler(request.content)
            return false
        }

        return implementation.didReceive(request, withContentHandler: contentHandler)
    }

    /**
     iOS telling the notification service to hurry up and stop modifying the push notifications.
     Stop all network requests and modifying and show the push for what it looks like now.
     */
    public func serviceExtensionTimeWillExpire() {
        implementation?.serviceExtensionTimeWillExpire()
    }
    #endif

    /// Dispatches a background flush of any pending push delivery metrics persisted by the NSE.
    /// Must be called after ``DIGraphShared/registerPendingPushDeliveryStore()`` so the store reflects
    /// the correct app group. Skipped entirely when ``DataPipelineTracking`` is unavailable — metrics
    /// are preserved in the store for a future launch where DataPipeline is present.
    private static func schedulePendingPushDeliveryMetricsFlush() {
        Task.detached(priority: .utility) {
            let store = DIGraphShared.shared.pendingPushDeliveryStore
            let logger = DIGraphShared.shared.logger
            let pending = store.loadAll()
            guard !pending.isEmpty else {
                logger.debug("Pending push delivery store: nothing to flush on MessagingPush startup")
                return
            }

            guard let pipeline = DIGraphShared.shared.getOptional(DataPipelineTracking.self) else {
                logger.debug("Pending push delivery store: DataPipeline unavailable, skipping flush to preserve \(pending.count) metric(s)")
                return
            }
            logger.debug("Pending push delivery store: flushing \(pending.count) metric(s) on MessagingPush startup")
            pending.forEach { metric in
                pipeline.trackDeliveryEvent(
                    token: metric.deviceToken,
                    event: metric.event.rawValue,
                    deliveryId: metric.deliveryId,
                    timestamp: metric.timestamp.string(format: .iso8601WithMilliseconds)
                )
            }
            let ids = Set(pending.map(\.id))
            if !store.removeAll(ids: ids) {
                logger.error(
                    "Pending push delivery store: failed to remove \(ids.count) flushed metric(s) (rows may re-send on next launch)"
                )
            }
            logger.debug("Pending push delivery store: finished flush attempt for \(pending.count) metric(s) on MessagingPush startup")
        }
    }
}

// Convenient way for other modules to access instance as well as being able to mock instance in tests.
public extension DIGraphShared {
    var messagingPushInstance: MessagingPushInstance {
        if let override: MessagingPushInstance = getOverriddenInstance() {
            return override
        }

        return MessagingPush.shared
    }
}

extension DIGraphShared {
    /// Re-registers ``PendingPushDeliveryStore`` using the push module config's `appGroupId` so rich push / NSE use the customer-configured app group (or bundle inference when `nil`).
    func registerPendingPushDeliveryStore() {
        registerPendingPushDeliveryStore(appGroupId: messagingPushConfigOptions.appGroupId)
    }

    #if canImport(UserNotifications)
    /// Production: new `RichPushHttpClient` per notification (isolated cancel). Tests: use DI overrides when set.
    func makeNSEScopedHttpClientAndDeliveryTracker() -> (HttpClient, RichPushDeliveryTracker) {
        let nseHttpClient: HttpClient
        if let overridden: HttpClient = getOverriddenInstance() {
            nseHttpClient = overridden
        } else {
            nseHttpClient = RichPushHttpClient(
                jsonAdapter: jsonAdapter,
                httpRequestRunner: httpRequestRunner,
                logger: logger,
                userAgentUtil: userAgentUtil
            )
        }

        let deliveryTracker: RichPushDeliveryTracker
        if let overridden: RichPushDeliveryTracker = getOverriddenInstance() {
            deliveryTracker = overridden
        } else {
            deliveryTracker = RichPushDeliveryTrackerImpl(httpClient: nseHttpClient, logger: logger)
        }

        return (nseHttpClient, deliveryTracker)
    }
    #endif
}
