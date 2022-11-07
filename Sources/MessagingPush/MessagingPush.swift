import CioTracking
import Common
import Foundation
#if canImport(UserNotifications) && canImport(UIKit)
import UIKit
import UserNotifications
#endif

/**
 Swift code goes into this module that are common to *all* of the Messaging Push modules (APN, FCM, etc).
 So, performing an HTTP request to the API with a device token goes here.
  */
public class MessagingPush: ModuleTopLevelObject<MessagingPushInstance>, MessagingPushInstance {
    @Atomic public private(set) static var shared = MessagingPush()

    // testing constructor
    override internal init(implementation: MessagingPushInstance, sdkInitializedUtil: SdkInitializedUtil) {
        super.init(implementation: implementation, sdkInitializedUtil: sdkInitializedUtil)
    }

    // singleton constructor
    override private init() {
        super.init()
    }

    // for testing
    internal static func resetSharedInstance() {
        Self.shared = MessagingPush()
    }

    public static func initialize() {
        MessagingPush.shared.initialize()
    }

    override public func inititlize(siteId: SiteId, diGraph: DIGraph) {
        let logger = diGraph.logger
        logger.debug("Setting up MessagingPush module...")

        // Register MessagingPush module hooks now that the module is being initialized.
        let hooks = diGraph.hooksManager
        let moduleHookProvider = MessagingPushModuleHookProvider()
        hooks.add(key: .messagingPush, provider: moduleHookProvider)

        logger.info("MessagingPush module setup with SDK")
    }

    override public func getImplementationInstance(siteId: SiteId, diGraph: DIGraph) -> MessagingPushInstance {
        MessagingPushImplementation(siteId: siteId, diGraph: diGraph)
    }

    /**
     Register a new device token with Customer.io, associated with the current active customer. If there
     is no active customer, this will fail to register the device
     */
    public func registerDeviceToken(_ deviceToken: String) {
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
