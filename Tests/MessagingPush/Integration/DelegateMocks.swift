import UIKit
import ObjectiveC

// Custom UIApplicationDelegate mock
class MockAppDelegate: NSObject, UIApplicationDelegate {
    var didFinishLaunchingCalled = false
    var didRegisterForRemoteNotificationsCalled = false
    var didFailToRegisterForRemoteNotificationsCalled = false
    var didBecomeActiveCalled = false
    var continueUserActivityCalled = false
    var launchOptionsReceived: [UIApplication.LaunchOptionsKey: Any]?
    var deviceTokenReceived: Data?
    var errorReceived: Error?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        didFinishLaunchingCalled = true
        launchOptionsReceived = launchOptions
        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        didRegisterForRemoteNotificationsCalled = true
        deviceTokenReceived = deviceToken
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        didFailToRegisterForRemoteNotificationsCalled = true
        errorReceived = error
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        didBecomeActiveCalled = true
    }
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        continueUserActivityCalled = true
        return true
    }
}

// Custom UNUserNotificationCenterDelegate mock
class MockNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    var didReceiveNotificationResponseCalled = false
    var willPresentNotificationCalled = false
    var openSettingsForNotificationCalled = false
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        didReceiveNotificationResponseCalled = true
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        willPresentNotificationCalled = true
        completionHandler([])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        openSettingsForNotificationCalled = true
    }
    
}

extension UNUserNotificationCenter {
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
