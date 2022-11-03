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
public class MessagingPush: MessagingPushInstance {
    @Atomic public private(set) static var shared = MessagingPush()

    private var _implementation: MessagingPushInstance?
    // Only create implementation class after SDK has been initialized. Otherwise, you run the risk of requests being
    // ignored even after SDK has been inititlized.
    internal var implementation: MessagingPushInstance? {
        _implementation ?? createAndSetImplementationInstance()
    }

    private let sdkInitializedUtil: SdkInitializedUtil

    // for writing tests
    internal init(implementation: MessagingPushInstance, sdkInitializedUtil: SdkInitializedUtil) {
        self._implementation = implementation
        self.sdkInitializedUtil = sdkInitializedUtil
    }

    // singleton constructor
    private init() {
        self.sdkInitializedUtil = SdkInitializedUtilImpl()
    }

    private func createAndSetImplementationInstance() -> MessagingPushImplementation? {
        guard let postSdkInitializedData = sdkInitializedUtil.postInitializedData else {
            // SDK not yet initialized. Don't run the code.
            return nil
        }

        let diGraph = postSdkInitializedData.diGraph
        let siteId = postSdkInitializedData.siteId

        let logger = diGraph.logger
        logger.debug("Setting up MessagingPush module...")

        // Register MessagingPush module hooks now that the module is being initialized.
        let hooks = diGraph.hooksManager
        let moduleHookProvider = MessagingPushModuleHookProvider(siteId: siteId)
        hooks.add(key: .messagingPush, provider: moduleHookProvider)

        let newInstance = MessagingPushImplementation(siteId: siteId, diGraph: diGraph)
        _implementation = newInstance

        logger.info("MessagingPush module setup with SDK")

        return newInstance
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
