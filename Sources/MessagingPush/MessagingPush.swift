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
    // testing constructor
    init(implementation: MessagingPushInstance?, globalDataStore: GlobalDataStore) {
        self.globalDataStore = globalDataStore
        super.init(moduleName: Self.moduleName, implementation: implementation)
    }

    // singleton constructor
    private init() {
        self.globalDataStore = CioGlobalDataStore.getInstance()
        super.init(moduleName: Self.moduleName)
    }

    // for testing
    static func resetSharedInstance() {
        shared = MessagingPush()
    }

    /**
     Initialize the shared `instance` of `MessagingPush`.
     Call this function when your app launches, before using `MessagingPush.shared`.
     */
    @discardableResult
    public static func initialize(
        configure configureHandler: ((inout MessagingPushConfigOptions) -> Void)? = nil
    ) -> MessagingPushInstance {
        var configOptions = moduleConfig

        if let configureHandler = configureHandler {
            configureHandler(&configOptions)
        }

        shared.initializeModule()
        return shared
    }

    private func initializeModule() {
        guard getImplementationInstance() == nil else {
            logger.info("\(moduleName) module is already initialized. Ignoring redundant initialization request.")
            return
        }

        logger.debug("Setting up \(moduleName) module...")
        let pushImplementation = MessagingPushImplementation(diGraph: DIGraphShared.shared, moduleConfig: Self.moduleConfig)
        setImplementationInstance(implementation: pushImplementation)

        logger.info("\(moduleName) module successfully set up with SDK")
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
