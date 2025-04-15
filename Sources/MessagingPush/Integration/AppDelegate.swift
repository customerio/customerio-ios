import UIKit
import CioDataPipelines
// import CioMessagingPush

public typealias AppDelegateType = NSObject & UIApplicationDelegate

open class AppDelegate: AppDelegateType, UNUserNotificationCenterDelegate {
    package let messagingPush: MessagingPush
    
    private let wrappedAppDelegate: UIApplicationDelegate?
    private var wrappedNoticeCenterDelegate: UNUserNotificationCenterDelegate?

    // Flag to control whether to set the UNUserNotificationCenter delegate
    open var shouldSetNotificationCenterDelegate: Bool {
        return true
    }
    
    public override convenience init() {
        self.init(messagingPush: MessagingPush.shared, appDelegate: nil)
    }
    
    public init(messagingPush: MessagingPush, appDelegate: AppDelegateType? = nil) {
        self.messagingPush = messagingPush
        self.wrappedAppDelegate = appDelegate
        super.init()
    }
    
    open func application(_ application: UIApplication,
                            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let result = wrappedAppDelegate?.application?(application, didFinishLaunchingWithOptions: launchOptions)
        
        application.registerForRemoteNotifications()
        
        if shouldSetNotificationCenterDelegate {
            wrappedNoticeCenterDelegate = UNUserNotificationCenter.current().delegate
            UNUserNotificationCenter.current().delegate = self
        }
        
        return result ?? true
    }
    
    open func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        wrappedAppDelegate?.application?(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }
    
    open func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
        wrappedAppDelegate?.application?(application, didFailToRegisterForRemoteNotificationsWithError: error)
        
        messagingPush.deleteDeviceToken()
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    // Function called when a push notification is clicked or swiped away.
    open func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
        let _ = messagingPush.userNotificationCenter(center, didReceive: response)
        
        if let wrappedNoticeCenterDelegate = wrappedNoticeCenterDelegate,
           wrappedNoticeCenterDelegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)))
        {
            wrappedNoticeCenterDelegate.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
        } else {
            completionHandler()
        }
    }
    
    // MARK: - method forwarding
    override public func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) {
            return true
        }
        return wrappedAppDelegate?.responds(to: aSelector) ?? false
    }
    
    override public func forwardingTarget(for aSelector: Selector!) -> Any? {
        if super.responds(to: aSelector) {
            return self
        }
        if let wrappedAppDelegate = wrappedAppDelegate,
           wrappedAppDelegate.responds(to: aSelector) {
            return wrappedAppDelegate
        }
        return nil
    }
}
