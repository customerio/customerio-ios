import CioTracking
import Common
import Foundation

/**
 Swift code goes into this module that are common to *all* of the Messaging Push modules (APN, FCM, etc).
 So, performing an HTTP request to the API with a device token goes here.
  */
public class MessagingPush: ModuleTopLevelObject<MessagingPushInstance>, MessagingPushInstance {
    @Atomic public private(set) static var shared = MessagingPush()

    // testing constructor
    override internal init(implementation: MessagingPushInstance?, globalDataStore: GlobalDataStore, sdkInitializedUtil: SdkInitializedUtil) {
        super.init(implementation: implementation, globalDataStore: globalDataStore, sdkInitializedUtil: sdkInitializedUtil)
    }

    // singleton constructor
    override private init() {
        super.init()
    }

    // for testing
    internal static func resetSharedInstance() {
        Self.shared = MessagingPush()
    }

    // At this time, we do not require `MessagingPush.initialize()` to be called to make the SDK work. There is
    // currently no module initialization to perform.
    public static func initialize() {
        MessagingPush.shared.initializeModuleIfSdkInitialized()
    }

    override public func inititlizeModule(diGraph: DIGraph) {
        let logger = diGraph.logger
        logger.debug("Setting up MessagingPush module...")

        logger.info("MessagingPush module setup with SDK")
    }

    override public func getImplementationInstance(diGraph: DIGraph) -> MessagingPushInstance {
        MessagingPushImplementation(diGraph: diGraph)
    }

    /**
     Register a new device token with Customer.io, associated with the current active customer. If there
     is no active customer, this will fail to register the device
     */
    public func registerDeviceToken(_ deviceToken: String) {
        globalDataStore.pushDeviceToken = deviceToken
        implementation?.registerDeviceToken(deviceToken)
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
