import CioInternalCommon
@_spi(Internal) import CioMessagingPush
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

// Some functions are copied from MessagingPush because
// 1. This allows the generated mock to contain these functions
// 2. Customers do not need to `import CioMessaginPush`. Only 1 import: `CioMessaginPushFCM`.
public protocol MessagingPushFCMInstance: AutoMockable {
    func registerDeviceToken(fcmToken: String?)

    // sourcery:Name=didReceiveRegistrationToken
    func messaging(
        _ messaging: Any,
        didReceiveRegistrationToken fcmToken: String?
    )

    // sourcery:Name=didFailToRegisterForRemoteNotifications
    func application(
        _ application: Any,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    )

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
    #endif
}

typealias MessagingPushInstanceImplementation = (_ config: MessagingPushConfigOptions) -> MessagingPushInstance

enum MessagingPushFCMDependencies {
    @available(iOSApplicationExtension, unavailable)
    static var initializeImplementation: MessagingPushInstanceImplementation = { config in
        MessagingPush.initialize(withConfig: config)
    }

    @available(iOS, unavailable)
    @available(visionOS, unavailable)
    @available(iOSApplicationExtension, introduced: 13.0)
    @available(visionOSApplicationExtension, introduced: 1.0)
    static var initializeImplementationForExtension: MessagingPushInstanceImplementation = { config in
        MessagingPush.initializeForExtension(withConfig: config)
    }

    @available(iOSApplicationExtension, unavailable)
    static var setupAutoFetchDeviceToken: () -> Void = {
        let pushConfigOptions = MessagingPush.moduleConfig
        if pushConfigOptions.autoFetchDeviceToken, !MessagingPush.appDelegateIntegratedExplicitly {
            let apnAutoFetchDeviceToken = FCMAutoFetchDeviceTokenImpl(messagingPushFCM: MessagingPushFCM.shared)
            apnAutoFetchDeviceToken.setup()
        }
    }

    static var messagingPushProvider: () -> MessagingPushInstance = { MessagingPush.shared }
}

public class MessagingPushFCM: MessagingPushFCMInstance {
    static let shared = MessagingPushFCM()

    var messagingPush: MessagingPushInstance {
        MessagingPushFCMDependencies.messagingPushProvider()
    }

    public func registerDeviceToken(fcmToken: String?) {
        guard let deviceToken = fcmToken else {
            return
        }
        messagingPush.registerDeviceToken(deviceToken)
    }

    public func messaging(_ messaging: Any, didReceiveRegistrationToken fcmToken: String?) {
        guard let deviceToken = fcmToken else {
            return
        }
        registerDeviceToken(fcmToken: deviceToken)
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

    /**
     Initialize and configure `MessagingPushFCM`.
     Call this function in your app if you want to initialize and configure the module to
     auto-fetch device token and auto-register device with Customer.io.
     */
    @discardableResult
    @available(iOSApplicationExtension, unavailable)
    public static func initialize(
        withConfig config: MessagingPushConfigOptions = MessagingPushConfigBuilder().build()
    ) -> MessagingPushInstance {
        // initialize module with features shared by APN and FCM modules
        let implementation = MessagingPushFCMDependencies.initializeImplementation(config)
        // Setup autoFetchDeviceToken
        MessagingPushFCMDependencies.setupAutoFetchDeviceToken()

        return implementation
    }

    /// MessagingPushFCM initializer for Notification Service Extension
    @available(iOS, unavailable)
    @available(visionOS, unavailable)
    @available(iOSApplicationExtension, introduced: 13.0)
    @available(visionOSApplicationExtension, introduced: 1.0)
    @discardableResult
    public static func initializeForExtension(withConfig config: MessagingPushConfigOptions) -> MessagingPushInstance {
        let implementation = MessagingPushFCMDependencies.initializeImplementationForExtension(config)
        return implementation
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

    @available(iOSApplicationExtension, unavailable)
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) -> CustomerIOParsedPushPayload? {
        messagingPush.userNotificationCenter(center, didReceive: response)
    }

    @available(iOSApplicationExtension, unavailable)
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) -> Bool {
        messagingPush.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }
    #endif
}
