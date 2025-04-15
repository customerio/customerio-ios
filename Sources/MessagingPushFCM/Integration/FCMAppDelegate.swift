import UIKit
import CioMessagingPush
import FirebaseMessaging

open class FCMAppDelegate: AppDelegate, MessagingDelegate {
    private var wrappedMessagingDelegate: MessagingDelegate?
    
    open var shouldSetMessagingDelegate: Bool {
        return true
    }

    public convenience init() {
        self.init(messagingPush: MessagingPush.shared, appDelegate: nil)
    }

    public override init(messagingPush: MessagingPush, appDelegate: AppDelegateType? = nil) {
        super.init(messagingPush: messagingPush, appDelegate: appDelegate)
    }
    
    public override func application(_ application: UIApplication,
                            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
        
        if shouldSetMessagingDelegate {
            wrappedMessagingDelegate = Messaging.messaging().delegate
            Messaging.messaging().delegate = self
        }
        
        return result
    }
    
    public override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
        
        if Messaging.messaging().apnsToken == deviceToken {
            return
        }
        Messaging.messaging().apnsToken = deviceToken
    }
    
    // MARK: - MessagingDelegate
    public func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let wrappedMessagingDelegate,
           wrappedMessagingDelegate.responds(to: #selector(MessagingDelegate.messaging(_:didReceiveRegistrationToken:))) {
            wrappedMessagingDelegate.messaging?(messaging, didReceiveRegistrationToken: fcmToken)
        }
        
        // Forward the device token to the Customer.io SDK:
        MessagingPush.shared.registerDeviceToken(fcmToken: fcmToken)
    }
}

open class FCMAppDelegateWrapper<UserAppDelegate: AppDelegateType>: FCMAppDelegate {
    public init() {
        super.init(messagingPush: MessagingPush.shared, appDelegate: UserAppDelegate())
    }
}