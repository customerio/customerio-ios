import CioInternalCommon
import UIKit
@_spi(Internal) import CioMessagingPush

@available(iOSApplicationExtension, unavailable)
open class CioAppDelegate: CioProviderAgnosticAppDelegate, FirebaseServiceDelegate {
    /// Temporary solution, until interfaces MessagingPushInstance/MessagingPushAPNInstance/MessagingPushFCMInstance are fixed
    private var messagingPushFCM: MessagingPushFCMInstance? {
        messagingPush as? MessagingPushFCMInstance
    }

    private var firebaseService: FirebaseService?
    private var wrappedFirebaseDelegate: FirebaseServiceDelegate?

    public convenience init() {
        DIGraphShared.shared.logger.error("CIO: This no-argument initializer should not to be used. Added since UIKit's AppDelegate initialization process crashes if for no-arg init is missing.")
        self.init(
            messagingPush: MessagingPush.shared,
            appDelegate: nil,
            logger: DIGraphShared.shared.logger
        )
    }

    override public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

        if config?().autoFetchDeviceToken ?? false {
            if var service = MessagingPushFCM.shared.firebaseMessaging() {
                wrappedFirebaseDelegate = service.delegate
                service.delegate = self
            } else {
                DIGraphShared.shared.logger.error("CIO: firebaseService is nil. Make sure to initialize the MessagingPushFCM SDK before use.")
            }
        }

        return result
    }

    override open func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)

        guard config?().autoFetchDeviceToken ?? false else { return }

        MessagingPushFCM.shared.fetchFirebaseRegistration(apnsToken: deviceToken) { [messagingPushFCM] token in
            messagingPushFCM?.registerDeviceToken(fcmToken: token)
        }
    }

    // MARK: - FirebaseServiceDelegate

    public func didReceiveRegistrationToken(_ token: String?) {
        if let wrappedFirebaseDelegate {
            wrappedFirebaseDelegate.didReceiveRegistrationToken(token)
        }

        // Forward the device token to the Customer.io SDK:
        messagingPushFCM?.registerDeviceToken(fcmToken: token)
    }

    public func didReceiveRegistration(_ installationId: String?) {
        wrappedFirebaseDelegate?.didReceiveRegistration(installationId)

        messagingPushFCM?.messaging(self, didReceiveRegistration: installationId)
    }
}

@available(iOSApplicationExtension, unavailable)
open class CioAppDelegateWrapper<UserAppDelegate: CioAppDelegateType>: CioAppDelegate {
    public init() {
        super.init(
            messagingPush: MessagingPush.shared,
            appDelegate: UserAppDelegate(),
            config: { MessagingPush.moduleConfig },
            logger: DIGraphShared.shared.logger
        )
    }
}
