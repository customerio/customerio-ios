import CioInternalCommon
import UIKit
@_spi(Internal) import CioMessagingPush
import FirebaseMessaging

public typealias FirebaseMessagingInstance = () -> FirebaseMessagingIntegration

// sourcery: AutoMockable
public protocol FirebaseMessagingIntegration {
    var delegate: MessagingDelegate? { get set }
    var apnsToken: Data? { get set }
}

extension Messaging: FirebaseMessagingIntegration {}

@available(iOSApplicationExtension, unavailable)
open class CioAppDelegateFCM: CioAppDelegate, MessagingDelegate {
    /// Temporary solution, until interfaces MessagingPushInstance/MessagingPushAPNInstance/MessagingPushFCMInstance are fixed
    private var messagingPushFCM: MessagingPushFCMInstance? {
        messagingPush as? MessagingPushFCMInstance
    }

    private var firebaseMessaging: FirebaseMessagingInstance?
    private var wrappedMessagingDelegate: MessagingDelegate?

    open var shouldIntegrateWithFirebaseMessaging: Bool {
        true
    }

    public convenience init() {
        DIGraphShared.shared.logger.error("CIO: This no-argument CioAppDelegateFCM initializer is not intended to be used. Added for compatibility.")
        self.init(
            messagingPush: MessagingPush.shared,
            userNotificationCenter: nil,
            firebaseMessaging: nil,
            appDelegate: nil,
            logger: DIGraphShared.shared.logger
        )
    }

    public init(
        messagingPush: MessagingPushInstance,
        userNotificationCenter: UserNotificationCenterInstance?,
        firebaseMessaging: FirebaseMessagingInstance?,
        appDelegate: CioAppDelegateType? = nil,
        logger: Logger
    ) {
        self.firebaseMessaging = firebaseMessaging
        super.init(messagingPush: messagingPush, userNotificationCenter: userNotificationCenter, appDelegate: appDelegate, logger: logger)
    }

    override public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

        if shouldIntegrateWithFirebaseMessaging,
           var messaging = firebaseMessaging?() {
            wrappedMessagingDelegate = messaging.delegate
            messaging.delegate = self
        }

        return result
    }

    override public func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)

        if shouldIntegrateWithFirebaseMessaging,
           var messaging = firebaseMessaging?() {
            messaging.apnsToken = deviceToken
        }
    }

    // MARK: - MessagingDelegate

    public func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let wrappedMessagingDelegate,
           wrappedMessagingDelegate.responds(to: #selector(MessagingDelegate.messaging(_:didReceiveRegistrationToken:))) {
            wrappedMessagingDelegate.messaging?(messaging, didReceiveRegistrationToken: fcmToken)
        }

        // Forward the device token to the Customer.io SDK:
        messagingPushFCM?.registerDeviceToken(fcmToken: fcmToken)
    }
}

@available(iOSApplicationExtension, unavailable)
open class CioAppDelegateFCMWrapper<UserAppDelegate: CioAppDelegateType>: CioAppDelegateFCM {
    public init() {
        super.init(
            messagingPush: MessagingPush.shared,
            userNotificationCenter: { UNUserNotificationCenter.current() },
            firebaseMessaging: { Messaging.messaging() },
            appDelegate: UserAppDelegate(),
            logger: DIGraphShared.shared.logger
        )
    }
}
