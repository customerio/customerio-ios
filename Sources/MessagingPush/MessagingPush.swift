import CioTracking
import Common
import Foundation
#if canImport(UserNotifications) && canImport(UIKit)
import UIKit
import UserNotifications
#endif

// Used for mocking. Some functions do not exist such as ones used for deep linking or rich push as they are
// disabled in app extensions.
public protocol MessagingPushInstance {
    func registerDeviceToken(_ deviceToken: String)
    func deleteDeviceToken()
    func trackMetric(
        deliveryID: String,
        event: Metric,
        deviceToken: String
    )

    @discardableResult
    func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) -> Bool

    func serviceExtensionTimeWillExpire()
}

/**
 Swift code goes into this module that are common to *all* of the Messaging Push modules (APN, FCM, etc).
 So, performing an HTTP request to the API with a device token goes here.
  */

public class MessagingPush: MessagingPushInstance {
    @Atomic public private(set) static var shared = MessagingPush(customerIO: CustomerIO.shared)

    public let customerIO: CustomerIOInstance!
    internal var implementation: MessagingPushImplementation?

    /**
     Create a new instance of the `MessagingPush` class.

     - Parameters:
       - customerIO: Instance of `CustomerIO` class.
     */
    public init(customerIO: CustomerIOInstance) {
        self.customerIO = customerIO
        // XXX: customers may want to know if siteId nil. Log it to them to help debug.
        if let siteId = customerIO.siteId {
            let diGraphTracking = DIGraph.getInstance(siteId: siteId)
            let logger = diGraphTracking.logger

            logger.info("MessagingPush module setup with SDK")
            // Register MessagingPush module hooks now that the module is being initialized.
            let hooks = diGraphTracking.hooksManager
            let moduleHookProvider = MessagingPushModuleHookProvider(siteId: siteId)

            hooks.add(key: .messagingPush, provider: moduleHookProvider)

            self.implementation = MessagingPushImplementation(siteId: siteId)
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

@available(iOSApplicationExtension, unavailable)
public extension MessagingPush {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) -> Bool {
        guard let implementation = implementation else {
            completionHandler()
            return false
        }

        return implementation.userNotificationCenter(center, didReceive: response,
                                                     withCompletionHandler: completionHandler)
    }
}
