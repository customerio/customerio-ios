import UIKit
import ObjectiveC

// Custom UIApplicationDelegate mock
public class MockAppDelegate: NSObject, UIApplicationDelegate {
    public var didFinishLaunchingCalled = false
    public var didRegisterForRemoteNotificationsCalled = false
    public var didFailToRegisterForRemoteNotificationsCalled = false
    public var didBecomeActiveCalled = false
    public var continueUserActivityCalled = false
    public var launchOptionsReceived: [UIApplication.LaunchOptionsKey: Any]?
    public var deviceTokenReceived: Data?
    public var errorReceived: Error?
    
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        didFinishLaunchingCalled = true
        launchOptionsReceived = launchOptions
        return true
    }
    
    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        didRegisterForRemoteNotificationsCalled = true
        deviceTokenReceived = deviceToken
    }
    
    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        didFailToRegisterForRemoteNotificationsCalled = true
        errorReceived = error
    }
    
    public func applicationDidBecomeActive(_ application: UIApplication) {
        didBecomeActiveCalled = true
    }
    
    public func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        continueUserActivityCalled = true
        return true
    }
}

// Custom UNUserNotificationCenterDelegate mock
public class MockNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    public  var didReceiveNotificationResponseCalled = false
    public var willPresentNotificationCalled = false
    public var openSettingsForNotificationCalled = false
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        didReceiveNotificationResponseCalled = true
        completionHandler()
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        willPresentNotificationCalled = true
        completionHandler([])
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        openSettingsForNotificationCalled = true
    }
    
}

public extension UNUserNotificationCenter {
    static func swizzleNotificationCenter() {
        let originalMethod = class_getClassMethod(UNUserNotificationCenter.self, #selector(UNUserNotificationCenter.current))!
        let swizzledMethod = class_getClassMethod(UNUserNotificationCenter.self, #selector(UNUserNotificationCenter.currentMock))!
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
    
    static func unswizzleNotificationCenter() {
        swizzleNotificationCenter() // Calling again will swap back
    }
    
    @objc class func currentMock() -> UNUserNotificationCenter {
        let dummyObject = NSObject()
        let notificationCenter = unsafeBitCast(dummyObject, to: UNUserNotificationCenter.self)
        return notificationCenter
    }
}
