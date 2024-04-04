import CioInternalCommon
import Foundation

/**
 Swift code goes into this module that are common to *all* of the Messaging Push modules (APN, FCM, etc).
 So, performing an HTTP request to the API with a device token goes here.
  */
public class MessagingPush: ModuleTopLevelObject<MessagingPushInstance>, MessagingPushInstance {
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
            if config.autoTrackPushEvents {
                DIGraphShared.shared.automaticPushClickHandling.start()
            }

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
