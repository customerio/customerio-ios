import ObjectiveC
import UIKit

// Custom UNUserNotificationCenterDelegate mock
public class MockNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    public var didReceiveNotificationResponseCalled = false
    public var willPresentNotificationCalled = false
    public var openSettingsForNotificationCalled = false
    public var respondsToSelectors: [Selector: Bool] = [
        #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:)): true,
        #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)): true,
        #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:openSettingsFor:)): true
    ]

    override public func responds(to aSelector: Selector!) -> Bool {
        if let shouldRespond = respondsToSelectors[aSelector] {
            return shouldRespond
        }
        return super.responds(to: aSelector)
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        willPresentNotificationCalled = true
        completionHandler([])
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        didReceiveNotificationResponseCalled = true
        completionHandler()
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        openSettingsForNotificationCalled = true
    }
}
