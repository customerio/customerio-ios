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
            userNotificationCenter: nil,
            appDelegate: nil,
            logger: DIGraphShared.shared.logger
        )
    }

    override public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

        if config?().autoFetchDeviceToken ?? false,
           var service = MessagingPushFCM.shared.firebaseService {
            wrappedFirebaseDelegate = service.delegate
            service.delegate = self
        }

        return result
    }

    // MARK: - FirebaseServiceDelegate

    public func didReceiveRegistrationToken(_ token: String?) {
        if let wrappedFirebaseDelegate {
            wrappedFirebaseDelegate.didReceiveRegistrationToken(token)
        }

        // Forward the device token to the Customer.io SDK:
        messagingPushFCM?.registerDeviceToken(fcmToken: token)
    }
}

@available(iOSApplicationExtension, unavailable)
open class CioAppDelegateWrapper<UserAppDelegate: CioAppDelegateType>: CioAppDelegate {
    public init() {
        super.init(
            messagingPush: MessagingPush.shared,
            userNotificationCenter: { UNUserNotificationCenter.current() },
            appDelegate: UserAppDelegate(),
            config: { MessagingPush.moduleConfig },
            logger: DIGraphShared.shared.logger
        )
    }
}
