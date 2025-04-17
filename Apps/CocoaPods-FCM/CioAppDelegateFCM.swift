//
//  CioAppDelegate.swift
//  APN UIKit
//
//  Created by Uros Milivojevic on 7.4.25..
//
import UIKit
import CioDataPipelines
import CioMessagingPushFCM
import FirebaseMessaging

public typealias CioAppDelegateType = NSObject & UIApplicationDelegate

open class CioAppDelegateFCM: CioAppDelegateType, UNUserNotificationCenterDelegate, MessagingDelegate {
    private let wrappedAppDelegate: CioAppDelegateType?
    private var wrappedMessagingDelegate: MessagingDelegate?
    private var wrappedNoticeCenterDelegate: UNUserNotificationCenterDelegate?

    // Flag to control whether to set the UNUserNotificationCenter delegate
    open var shouldSetNotificationCenterDelegate: Bool {
        return true
    }
    
    open var shouldSetMessagingDelegate: Bool {
        return true
    }
    
    public override convenience init() {
        self.init(appDelegate: nil)
    }
    
    public init(appDelegate: CioAppDelegateType? = nil) {
        self.wrappedAppDelegate = appDelegate
        super.init()
    }
    
    public func application(_ application: UIApplication,
                            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let result = wrappedAppDelegate?.application?(application, didFinishLaunchingWithOptions: launchOptions)
        
        application.registerForRemoteNotifications()
        
        if shouldSetMessagingDelegate {
            wrappedMessagingDelegate = Messaging.messaging().delegate
            Messaging.messaging().delegate = self
        }
        
        if shouldSetNotificationCenterDelegate {
            wrappedNoticeCenterDelegate = UNUserNotificationCenter.current().delegate
            UNUserNotificationCenter.current().delegate = self
        }
        
        return result ?? true
    }
    
    public func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        wrappedAppDelegate?.application?(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
        
//        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
//        print("📲 APNs Token: \(token)")
        if Messaging.messaging().apnsToken == deviceToken {
            return
        }
        Messaging.messaging().apnsToken = deviceToken
    }
    
    public func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
        wrappedAppDelegate?.application?(application, didFailToRegisterForRemoteNotificationsWithError: error)
        
//        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
        MessagingPush.shared.deleteDeviceToken()
    }
    
    // Silent/background push
    public func application(_ application: UIApplication,
                            didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                            fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
//        print("🕶️ Background/silent push received: \(userInfo)")
        
        if let wrappedAppDelegate,
           wrappedAppDelegate.responds(to: #selector(CioAppDelegateType.application(_:didReceiveRemoteNotification:fetchCompletionHandler:))) {
            wrappedAppDelegate.application?(
                application,
                didReceiveRemoteNotification: userInfo,
                fetchCompletionHandler: completionHandler
            )
        } else {
            // Register notification received ???
            completionHandler(.newData)
        }
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
   
    // MARK: - UNUserNotificationCenterDelegate
    // Function called when a push notification is clicked or swiped away.
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
        let _ = MessagingPush.shared.userNotificationCenter(center, didReceive: response)
        
        if let wrappedNoticeCenterDelegate,
           wrappedNoticeCenterDelegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)))
        {
            wrappedNoticeCenterDelegate.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
        } else {
            completionHandler()
        }
    }
    
    // To test sending of local notifications, display the push while app in foreground. So when you press the button to display local push in the app, you are able to see it and click on it.
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // pushEventHandler.shouldDisplayPushAppInForeground
        
        if let wrappedNoticeCenterDelegate = wrappedNoticeCenterDelegate,
           wrappedNoticeCenterDelegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:)))
        {
            wrappedNoticeCenterDelegate.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
        } else {
            completionHandler([.banner, .list, .badge, .sound])
        }
    }
    
    // TODO: do we need this?
//    public func userNotificationCenter(_ center: UNUserNotificationCenter,
//                                       openSettingsFor notification: UNNotification?) {
//        if let wrappedNoticeCenterDelegate = self.wrappedNoticeCenterDelegate,
//           wrappedNoticeCenterDelegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:openSettingsFor:))) {
//            wrappedNoticeCenterDelegate.userNotificationCenter?(center, openSettingsFor: notification)
//        }
//    }
    
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

open class CioAppDelegateWrapper<UserAppDelegate: CioAppDelegateType>: CioAppDelegateFCM {
    public init() {
        super.init(appDelegate: UserAppDelegate())
    }
}
