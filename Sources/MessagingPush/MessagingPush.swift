import CioInternalCommon
import Foundation

/**
 Swift code goes into this module that are common to *all* of the Messaging Push modules (APN, FCM, etc).
 So, performing an HTTP request to the API with a device token goes here.
  */
public class MessagingPush: ModuleTopLevelObject<MessagingPushInstance>, MessagingPushInstance {
    @Atomic public private(set) static var shared = MessagingPush()
    private static let moduleName = "MessagingPush"

    private var globalDataStore: GlobalDataStore

    // testing constructor
    init(implementation: MessagingPushInstance?, globalDataStore: GlobalDataStore) {
        self.globalDataStore = globalDataStore
        super.init(moduleName: MessagingPush.moduleName, implementation: implementation)
    }

    // singleton constructor
    private init() {
        self.globalDataStore = CioGlobalDataStore.getInstance()
        super.init(moduleName: MessagingPush.moduleName)
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
        var moduleConfig = MessagingPushConfigOptions.Factory.create()

        if let configureHandler = configureHandler {
            configureHandler(&moduleConfig)
        }

        shared.initialize(moduleConfig: moduleConfig)
        return shared
    }

    private func initialize(moduleConfig: MessagingPushConfigOptions) {
        if let pushImplementation = alreadyCreatedImplementation {
            pushImplementation.configure { $0.apply(moduleConfig) }
            logger.info("\(moduleName) module already initialized. Applying updated config, ignoring re-initialization request.")
            return
        }

        logger.debug("Setting up \(moduleName) module...")
        let pushImplementation = MessagingPushImplementation(diGraph: DIGraphShared.shared, moduleConfig: moduleConfig)
        setImplementationInstance(implementation: pushImplementation)

        // FIXME: [CDP] Update hooks to work as expected
        // Register MessagingPush module hooks now that the module is being initialized.
        // let hooks = diGraph.hooksManager
        // let moduleHookProvider = MessagingInAppModuleHookProvider()
        // hooks.add(key: .messagingInApp, provider: moduleHookProvider)
        logger.info("\(moduleName) module successfully set up with SDK")
    }

    override public func getImplementationInstance() -> MessagingPushInstance? {
        MessagingPush.initialize()
    }

    public func configure(with configureHandler: @escaping ((inout MessagingPushConfigOptions) -> Void)) {
        implementation?.configure(with: configureHandler)
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
