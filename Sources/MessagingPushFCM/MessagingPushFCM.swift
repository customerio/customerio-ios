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

public class MessagingPushFCM: MessagingPushFCMInstance {
    public static let shared = MessagingPushFCM()

    var messagingPush: MessagingPushInstance {
        MessagingPush.shared
    }

    var firebaseService: FirebaseService?
    private var wrappedFirebaseDelegate: FirebaseServiceDelegate?

    func firebaseMessaging() -> FirebaseService? {
        firebaseService
    }

    public func registerDeviceToken(fcmToken: String?) {
        guard let deviceToken = fcmToken else {
            return
        }
        messagingPush.registerDeviceToken(deviceToken)
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
    public static func internalSetup(
        withConfig config: MessagingPushConfigOptions = MessagingPushConfigBuilder().build(),
        firebaseService: FirebaseService
    ) -> MessagingPushInstance {
        // initialize parent module to initialize features shared by APN and FCM modules
        let implementation = MessagingPush.initialize(withConfig: config)

        shared.firebaseService = firebaseService

        let pushConfigOptions = MessagingPush.moduleConfig
        if pushConfigOptions.autoFetchDeviceToken {
            if var service = shared.firebaseMessaging() {
                shared.wrappedFirebaseDelegate = service.delegate
                service.delegate = shared
            } else {
                DIGraphShared.shared.logger.error(
                    "CIO: firebaseService is nil. Make sure to initialize the MessagingPushFCM SDK before use."
                )
            }
        }

        return implementation
    }

    /// MessagingPushFCM initializer for Notification Service Extension
    @available(iOS, unavailable)
    @available(visionOS, unavailable)
    @available(iOSApplicationExtension, introduced: 13.0)
    @available(visionOSApplicationExtension, introduced: 1.0)
    @discardableResult
    public static func initializeForExtension(withConfig config: MessagingPushConfigOptions)
        -> MessagingPushInstance
    {
        let implementation = MessagingPush.initializeForExtension(withConfig: config)
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
            // Use concrete MessagingPush instance since method was removed from protocol
            MessagingPush.shared.userNotificationCenter(center, didReceive: response)
        }

        @available(iOSApplicationExtension, unavailable)
        public func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) -> Bool {
            // Use concrete MessagingPush instance since method was removed from protocol
            MessagingPush.shared.userNotificationCenter(
                center, didReceive: response, withCompletionHandler: completionHandler)
        }
    #endif
}

// MARK: - FirebaseServiceDelegate

extension MessagingPushFCM: FirebaseServiceDelegate {
    /// Called by Firebase when a new FCM registration token is available.
    public func didReceiveRegistrationToken(_ token: String?) {
        if let wrappedFirebaseDelegate {
            wrappedFirebaseDelegate.didReceiveRegistrationToken(token)
        }
        registerDeviceToken(fcmToken: token)
    }
}
