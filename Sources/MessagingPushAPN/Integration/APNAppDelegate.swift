import CioInternalCommon
import UIKit
@_spi(Internal) import CioMessagingPush

@available(iOSApplicationExtension, unavailable)
open class APNAppDelegate: AppDelegate {
    /// Temporary solution, until interfaces MessagingPushInstance/MessagingPushAPNInstance/MessagingPushFCMInstance are fixed
    private var messagingPushAPN: MessagingPushAPNInstance? {
        messagingPush as? MessagingPushAPNInstance
    }

    public convenience init() {
        DIGraphShared.shared.logger.error("CIO: This no-argument APNAppDelegate initializer is not intended to be used. Added for compatibility.")
        self.init(
            messagingPush: MessagingPush.shared,
            userNotificationCenter: nil,
            appDelegate: nil,
            logger: DIGraphShared.shared.logger
        )
    }

    override public init(
        messagingPush: MessagingPushInstance,
        userNotificationCenter: UserNotificationCenterInstance?,
        appDelegate: AppDelegateType? = nil,
        logger: Logger
    ) {
        super.init(
            messagingPush: messagingPush,
            userNotificationCenter: userNotificationCenter,
            appDelegate: appDelegate,
            logger: logger
        )
    }

    override public func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)

        messagingPushAPN?.registerDeviceToken(apnDeviceToken: deviceToken)
    }
}

@available(iOSApplicationExtension, unavailable)
open class APNAppDelegateWrapper<UserAppDelegate: AppDelegateType>: APNAppDelegate {
    public init() {
        super.init(
            messagingPush: MessagingPush.shared,
            userNotificationCenter: { UNUserNotificationCenter.current() },
            appDelegate: UserAppDelegate(),
            logger: DIGraphShared.shared.logger
        )
    }
}
