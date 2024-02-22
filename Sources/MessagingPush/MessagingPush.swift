import CioInternalCommon
import Foundation

/**
 Swift code goes into this module that are common to *all* of the Messaging Push modules (APN, FCM, etc).
 So, performing an HTTP request to the API with a device token goes here.
  */
public class MessagingPush: ModuleTopLevelObject<MessagingPushInstance>, MessagingPushInstance {
    @Atomic public private(set) static var shared = MessagingPush()
    @Atomic public private(set) static var moduleConfig: MessagingPushConfigOptions = .Factory.create()

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
        shared.globalDataStore = diGraphShared.globalDataStore
        moduleConfig = config
        shared._implementation = implementation

        return implementation
    }

    @discardableResult
    static func setUpSharedInstanceForIntegrationTest(diGraphShared: DIGraphShared, config: MessagingPushConfigOptions) -> MessagingPushInstance {
        let implementation = MessagingPushImplementation(diGraph: diGraphShared, moduleConfig: Self.moduleConfig)
        return setUpSharedInstanceForUnitTest(implementation: implementation, diGraphShared: diGraphShared, config: config)
    }

    static func resetTestEnvironment() {
        moduleConfig = .Factory.create()
        shared = MessagingPush()
    }
    #endif

    /**
     Initialize the shared `instance` of `MessagingPush`.
     Call this function when your app launches, before using `MessagingPush.shared`.
     */
    @discardableResult
    @available(iOSApplicationExtension, unavailable)
    public static func initialize(
        configure configureHandler: ((inout MessagingPushConfigOptions) -> Void)? = nil
    ) -> MessagingPushInstance {
        shared.initializeModuleIfNotAlready {
            if let configureHandler = configureHandler {
                // pass current config reference to update it without needing to recreate
                configureHandler(&moduleConfig)
            }

            // Some part of the initialize is specific only to non-NSE targets.
            // Put those parts in this non-NSE initialize method.
            if Self.moduleConfig.autoTrackPushEvents {
                DIGraphShared.shared.automaticPushClickHandling.start()
            }

            return shared.getImplementation()
        }

        return shared
    }

    /// MessagingPush initializer for Notification Service Extension
    @available(iOS, unavailable)
    @available(iOSApplicationExtension, introduced: 13.0)
    @discardableResult
    public static func initialize(
        cdpApiKey: String,
        configure configureHandler: ((inout MessagingPushConfigOptions) -> Void)? = nil
    ) -> MessagingPushInstance {
        shared.initializeModuleIfNotAlready {
            if let configureHandler = configureHandler {
                configureHandler(&moduleConfig)
            }
            moduleConfig.cdpApiKey = cdpApiKey

            return shared.getImplementation()
        }

        return shared
    }

    private func getImplementation() -> MessagingPushInstance {
        MessagingPushImplementation(diGraph: DIGraphShared.shared, moduleConfig: Self.moduleConfig)
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
