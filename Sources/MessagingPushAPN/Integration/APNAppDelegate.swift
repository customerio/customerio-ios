import UIKit
import CioDataPipelines
import CioMessagingPush

open class APNAppDelegate: AppDelegate {
    
    public convenience init() {
        self.init(messagingPush: MessagingPush.shared, appDelegate: nil)
    }
    
    public override init(messagingPush: MessagingPush, appDelegate: AppDelegateType? = nil) {
        super.init(messagingPush: messagingPush, appDelegate: appDelegate)
    }
    
    public override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
        
        messagingPush.registerDeviceToken(apnDeviceToken: deviceToken)
    }
}

open class APNAppDelegateWrapper<UserAppDelegate: AppDelegateType>: APNAppDelegate {
    public init() {
        super.init(messagingPush: MessagingPush.shared, appDelegate: UserAppDelegate())
    }
}
