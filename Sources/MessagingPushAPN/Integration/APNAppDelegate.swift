import UIKit
@_spi(Internal) import CioMessagingPush
import CioInternalCommon

@available(iOSApplicationExtension, unavailable)
open class APNAppDelegate: AppDelegate {
    
    public convenience init() {
        self.init(messagingPush: MessagingPush.shared, appDelegate: nil, logger: DIGraphShared.shared.logger)
    }
    
    public override init(messagingPush: MessagingPush, appDelegate: AppDelegateType? = nil, logger: Logger) {
        super.init(messagingPush: messagingPush, appDelegate: appDelegate, logger: logger)
    }
    
    public override func application(_ application: UIApplication,
                                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
        
        messagingPush.registerDeviceToken(apnDeviceToken: deviceToken)
    }
}

@available(iOSApplicationExtension, unavailable)
open class APNAppDelegateWrapper<UserAppDelegate: AppDelegateType>: APNAppDelegate {
    public init() {
        super.init(messagingPush: MessagingPush.shared, appDelegate: UserAppDelegate(), logger: DIGraphShared.shared.logger)
    }
}
