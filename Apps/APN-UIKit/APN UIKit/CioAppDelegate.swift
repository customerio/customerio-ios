//
//  CioAppDelegate.swift
//  APN UIKit
//
//  Created by Uros Milivojevic on 7.4.25..
//
import UIKit
import CioDataPipelines
import CioMessagingPush

public typealias CioAppDelegateType = NSObject & UIApplicationDelegate

open class CioAppDelegate: CioAppDelegateType, UNUserNotificationCenterDelegate {
    private let wrappedAppDelegate: CioAppDelegateType?
    private var wrappedNoticeCenterDelegate: UNUserNotificationCenterDelegate?

    // Flag to control whether to set the UNUserNotificationCenter delegate
    open var shouldSetNotificationCenterDelegate: Bool {
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
        
        if shouldSetNotificationCenterDelegate {
            wrappedNoticeCenterDelegate = UNUserNotificationCenter.current().delegate
            UNUserNotificationCenter.current().delegate = self
        }
        
        return result ?? true
    }
    
    public func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        wrappedAppDelegate?.application?(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }
    
    public func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
        wrappedAppDelegate?.application?(application, didFailToRegisterForRemoteNotificationsWithError: error)
        
        MessagingPush.shared.deleteDeviceToken()
    }
    
    // Silent/background push
    // TODO: We don't need this in current iteration. Only if future if we want to read info from
    public func application(_ application: UIApplication,
                            didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                            fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
//        print("🕶️ Background/silent push received: \(userInfo)")
        
        if let wrappedAppDelegate = wrappedAppDelegate,
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
   
    // MARK: - UNUserNotificationCenterDelegate
    // Function called when a push notification is clicked or swiped away.
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
        let _ = MessagingPush.shared.userNotificationCenter(center, didReceive: response)
        
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
