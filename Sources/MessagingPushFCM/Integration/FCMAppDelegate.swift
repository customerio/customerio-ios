import CioInternalCommon
import UIKit
@_spi(Internal) import CioMessagingPush
import FirebaseMessaging

/// Usage
///
/// Issues with FirebaseMessaging implementation:
///  - for swizzled methods `application(_:didRegisterForRemoteNotificationsWithDeviceToken)`
///   and `application(_:didFailToRegisterForRemoteNotificationsWithError:)` original implementation is not called.
///   Because of this,, we are not able to forward calls to `wrappedAppDelegate` from our `AppDelegate`.
///   Check class `FIRMessagingRemoteNotificationsProxy.m` for more details.
///     - GULAppDelegateSwizzler has metod `application:donor_didRegisterForRemoteNotificationsWithDeviceToken:` which is not able to find our `application(_:didRegisterForRemoteNotificationsWithDeviceToken)`
///     - check the methods `createSubclassWithObject`/`proxyOriginalDelegateIncludingAPNSMethods`  in the same class, for full list of swizzled methods
   
@available(iOSApplicationExtension, unavailable)
open class FCMAppDelegate: AppDelegate, MessagingDelegate {
    private var wrappedMessagingDelegate: MessagingDelegate?

    open var shouldSetMessagingDelegate: Bool {
        true
    }

    public convenience init() {
        self.init(messagingPush: MessagingPush.shared, appDelegate: nil, logger: DIGraphShared.shared.logger)
    }

    override public init(messagingPush: MessagingPush, appDelegate: AppDelegateType? = nil, logger: Logger) {
        super.init(messagingPush: messagingPush, appDelegate: appDelegate, logger: logger)
    }

    override public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

        if shouldSetMessagingDelegate {
            wrappedMessagingDelegate = Messaging.messaging().delegate
            Messaging.messaging().delegate = self
        }

        return result
    }

    override public func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)

        Messaging.messaging().apnsToken = deviceToken
    }

    // MARK: - MessagingDelegate

    public func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let wrappedMessagingDelegate,
           wrappedMessagingDelegate.responds(to: #selector(MessagingDelegate.messaging(_:didReceiveRegistrationToken:))) {
            wrappedMessagingDelegate.messaging?(messaging, didReceiveRegistrationToken: fcmToken)
        }

        // Forward the device token to the Customer.io SDK:
        messagingPush.registerDeviceToken(fcmToken: fcmToken)
    }
}

@available(iOSApplicationExtension, unavailable)
open class FCMAppDelegateWrapper<UserAppDelegate: AppDelegateType>: FCMAppDelegate {
    public init() {
        super.init(messagingPush: MessagingPush.shared, appDelegate: UserAppDelegate(), logger: DIGraphShared.shared.logger)
    }
}
