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

    // sourcery:Name=didReceiveRegistration
    /// Registers the app's Firebase Installation ID (FID) with Customer.io.
    /// Call this from your `MessagingDelegate.messaging(_:didReceiveRegistration:)` when you register the device yourself.
    func messaging(
        _ messaging: Any,
        didReceiveRegistration installationId: String?
    )

    // sourcery:Name=didFailToRegisterForRemoteNotifications
    /// Logs the failure. The device stays registered with Customer.io.
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

// Default keeps conformers written before FID support compiling.
public extension MessagingPushFCMInstance {
    func messaging(_ messaging: Any, didReceiveRegistration installationId: String?) {}
}

public class MessagingPushFCM: MessagingPushFCMInstance {
    static let shared = MessagingPushFCM()

    var messagingPush: MessagingPushInstance {
        MessagingPush.shared
    }

    var firebaseService: FirebaseService?

    func firebaseMessaging() -> FirebaseService? {
        firebaseService
    }

    /// Gives Firebase the APNs token, then fetches the app's FCM registration: its FID in FID mode, otherwise its token.
    /// Fetching doesn't rely on the Firebase delegate, which the app may have replaced with its own.
    func fetchFirebaseRegistration(apnsToken: Data, onFetched: @escaping (String, DeviceTokenType) -> Void) {
        let logger = DIGraphShared.shared.logger
        guard let firebaseService = firebaseMessaging() else {
            logger.error("CIO: firebaseService is nil. Make sure to initialize the MessagingPushFCM SDK before use.")
            return
        }

        firebaseService.apnsToken = apnsToken

        guard firebaseService.isInstallationIdEnabled else {
            if Self.isInstallationIdEnabledInInfoPlist {
                logger.error("CIO: FirebaseMessagingInstallationIdEnabled is set, but FID registration isn't available. Registering FCM token instead. Update FirebaseMessaging and CioFirebaseWrapper to use FIDs.")
            }
            firebaseService.fetchToken { token, error in
                guard let token = token else {
                    logger.error("CIO: Failed to fetch FCM token: \(error?.localizedDescription ?? "unknown error")")
                    return
                }
                onFetched(token, .token)
            }
            return
        }

        firebaseService.fetchInstallationId { fid, error in
            guard let fid = fid else {
                logger.error("CIO: Failed to register Firebase Installation ID: \(error?.localizedDescription ?? "unknown error")")
                return
            }
            onFetched(fid, .fid)
        }
    }

    // Firebase's own setting for FID mode, read the way Firebase reads it. Only used to warn when the app's Firebase can't use it.
    private static var isInstallationIdEnabledInInfoPlist: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "FirebaseMessagingInstallationIdEnabled")
        return (value as? NSNumber)?.boolValue ?? (value as? NSString)?.boolValue ?? false
    }

    public func registerDeviceToken(fcmToken: String?) {
        guard let deviceToken = fcmToken else {
            return
        }
        messagingPush.registerDeviceToken(deviceToken)
    }

    public func messaging(_ messaging: Any, didReceiveRegistrationToken fcmToken: String?) {
        registerFirebaseDeviceToken(fcmToken, tokenType: .token)
    }

    /// Registers a value received from Firebase, along with its type.
    func registerFirebaseDeviceToken(_ deviceToken: String?, tokenType: DeviceTokenType) {
        guard let deviceToken = deviceToken else {
            return
        }
        MessagingPush.shared.registerDeviceToken(deviceToken, tokenType: tokenType)
    }

    public func messaging(_ messaging: Any, didReceiveRegistration installationId: String?) {
        registerFirebaseDeviceToken(installationId, tokenType: .fid)
    }

    public func application(_ application: Any, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        MessagingPush.shared.didFailToRegisterForRemoteNotifications(error: error)
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
        if pushConfigOptions.autoFetchDeviceToken, !MessagingPush.appDelegateIntegratedExplicitly {
            shared.setupAutoFetchDeviceToken()
        }

        return implementation
    }

    /// MessagingPushFCM initializer for Notification Service Extension
    @available(iOS, unavailable)
    @available(visionOS, unavailable)
    @available(iOSApplicationExtension, introduced: 13.0)
    @available(visionOSApplicationExtension, introduced: 1.0)
    @discardableResult
    public static func initializeForExtension(withConfig config: MessagingPushConfigOptions) -> MessagingPushInstance {
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
        MessagingPush.shared.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }
    #endif
}
