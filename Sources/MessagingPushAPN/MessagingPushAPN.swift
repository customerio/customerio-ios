import CioMessagingPush
import CioTracking
import Common
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

public protocol MessagingPushAPNInstance: AutoMockable {
    func registerDeviceToken(apnDeviceToken: Data)

    // sourcery:Name=didRegisterForRemoteNotifications
    func application(
        _ application: Any,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    )

    // sourcery:Name=didFailToRegisterForRemoteNotifications
    func application(
        _ application: Any,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    )

    // Some functions are copied from MessagingPush because
    // 1. This allows the generated mock to contain these functions
    // 2. Customers do not need to `import CioMessaginPush`. Only 1 import: `CioMessaginPushAPN`.
    func deleteDeviceToken()

    func trackMetric(
        deliveryID: String,
        event: Metric,
        deviceToken: String
    )

    #if canImport(UserNotifications)
    @discardableResult
    // sourcery:Name=didReceiveNotificationRequest
    // sourcery:IfCanImport=UserNotifications
    func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) -> Bool

    // sourcery:IfCanImport=UserNotifications
    func serviceExtensionTimeWillExpire()

    // sourcery:Name=userNotificationCenterReceivedResponse
    // sourcery:IfCanImport=UserNotifications
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) -> Bool
    #endif
}

public class MessagingPushAPN: MessagingPushAPNInstance {
    internal let messagingPush: MessagingPushInstance
    internal let customerIO: CustomerIOInstance!

    // for testing purposes
    internal init(messagingPush: MessagingPushInstance, customerIO: CustomerIOInstance) {
        self.messagingPush = messagingPush
        self.customerIO = customerIO
    }

    public init(customerIO: CustomerIOInstance) {
        self.customerIO = customerIO
        self.messagingPush = MessagingPush(customerIO: customerIO)
    }

    public func registerDeviceToken(apnDeviceToken: Data) {
        let deviceToken = String(apnDeviceToken: apnDeviceToken)
        messagingPush.registerDeviceToken(deviceToken)
    }

    public func application(_ application: Any, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        registerDeviceToken(apnDeviceToken: deviceToken)
    }

    public func application(_ application: Any, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        messagingPush.deleteDeviceToken()
    }

    public func deleteDeviceToken() {
        messagingPush.deleteDeviceToken()
    }

    public func trackMetric(deliveryID: String, event: Metric, deviceToken: String) {
        messagingPush.trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken)
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
        messagingPush.didReceive(request, withContentHandler: contentHandler)
    }

    /**
     iOS OS telling the notification service to hurry up and stop modifying the push notifications.
     Stop all network requests and modifying and show the push for what it looks like now.
     */
    public func serviceExtensionTimeWillExpire() {
        messagingPush.serviceExtensionTimeWillExpire()
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) -> Bool {
        messagingPush.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }
    #endif
}

// sourcery: InjectRegister = "DiPlaceholder"
internal class DiPlaceholder {}
