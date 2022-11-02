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

    internal var implementation: MessagingPushImplementation?

    // TODO: test that using mocked CustomerIOInstance will not break this code.
    internal init() {
        if let diGraph = CustomerIO.shared.diGraph, let siteId = CustomerIO.shared.siteId {
            let logger = diGraph.logger

            logger.info("MessagingPush module setup with SDK")
            // Register MessagingPush module hooks now that the module is being initialized.
            let hooks = diGraph.hooksManager
            let moduleHookProvider = MessagingPushModuleHookProvider(siteId: siteId)

            hooks.add(key: .messagingPush, provider: moduleHookProvider)

            self.implementation = MessagingPushImplementation(siteId: siteId, diGraph: diGraph)
        }
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
