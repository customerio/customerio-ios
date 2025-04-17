//
//  CioAPNAppDelegate.swift
//  APN UIKit
//
//  Created by Uros Milivojevic on 7.4.25..
//
import UIKit
import CioDataPipelines
import CioMessagingPushAPN

open class CioAPNAppDelegate: CioAppDelegate {
    
    public convenience init() {
        self.init(appDelegate: nil)
    }
    
    public override init(appDelegate: CioAppDelegateType? = nil) {
        super.init(appDelegate: appDelegate)
    }
    
    public override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
        
        MessagingPush.shared.registerDeviceToken(apnDeviceToken: deviceToken)
    }
}

open class CioAPNAppDelegateWrapper<UserAppDelegate: CioAppDelegateType>: CioAPNAppDelegate {
    public init() {
        super.init(appDelegate: UserAppDelegate())
    }
}
