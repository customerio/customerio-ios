import CioInternalCommon
import UIKit
@_spi(Internal) import CioMessagingPush

@available(iOSApplicationExtension, unavailable)
open class CioAppDelegate: CioProviderAgnosticAppDelegate {
    /// Temporary solution, until interfaces MessagingPushInstance/MessagingPushAPNInstance/MessagingPushFCMInstance are fixed
    private var messagingPushAPN: MessagingPushAPNInstance? {
        messagingPush as? MessagingPushAPNInstance
    }

    public convenience init() {
        DIGraphShared.shared.logger.error("CIO: This no-argument initializer should not to be used. Added since UIKit's AppDelegate initialization process crashes if for no-arg init is missing.")
        self.init(
            messagingPush: MessagingPush.shared,
            appDelegate: nil,
            config: nil,
            logger: DIGraphShared.shared.logger
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
