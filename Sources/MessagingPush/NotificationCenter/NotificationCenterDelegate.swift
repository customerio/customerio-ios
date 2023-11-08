import Foundation
import UserNotifications

@available(iOSApplicationExtension, unavailable)
public class CustomerIOUserNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = CustomerIOUserNotificationCenterDelegate()

    override private init() {}

    public static func setupCioPushClickHandling() {
        UNUserNotificationCenter.current().setupCioPushClickHandling()

        // Set our SDK as the click handler, if there isn't one already set in the app.
        if UNUserNotificationCenter.current().delegate == nil {
            UNUserNotificationCenter.current().delegate = CustomerIOUserNotificationCenterDelegate.shared

            // if another SDK or host app sets itself as the delegate, our SDK swizzled the delegate setter so we will be able to hook into the logic and still process pushes.
        } else {
            // This handles the case where a delegate may have already been assigned before our SDK is loaded into memory.
            // This re-assignment triggers NotifiationCenter.delegate setter that we swizzled so our SDK can swizzle in its logic.
            UNUserNotificationCenter.current().delegate = UNUserNotificationCenter.current().delegate
        }
    }

    public func setupSwizzling(delegate: UNUserNotificationCenterDelegate) {
        if delegate is CustomerIOUserNotificationCenterDelegate {
            return // avoid infinite loop. we dont want to swizzle our own delegate to avoid duplicate calls for push handling.
        }

        swizzle(
            targetClass: type(of: delegate),
            targetSelector: #selector(userNotificationCenter(_:didReceive:withCompletionHandler:)),
            myClass: CustomerIOUserNotificationCenterDelegate.self,
            mySelector: #selector(cio_swizzle_didReceive(_:didReceive:withCompletionHandler:))
        )
    }

    // Notification was interacted with.
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        _ = MessagingPush.shared.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }

    // called when a push is clicked.
    @objc dynamic func cio_swizzle_didReceive(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        _ = MessagingPush.shared.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)

        // continue swizzle
        cio_swizzle_didReceive(center, didReceive: response, withCompletionHandler: completionHandler)
    }
}

@available(iOSApplicationExtension, unavailable)
extension UNUserNotificationCenterDelegate {
    // called when a push is clicked.
    func cio_swizzle_didReceive(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        _ = MessagingPush.shared.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)

        // continue swizzle
        cio_swizzle_didReceive(center, didReceive: response, withCompletionHandler: completionHandler)
    }
}

@available(iOSApplicationExtension, unavailable)
extension UNUserNotificationCenter {
    func setupCioPushClickHandling() {
        let originalSelector = #selector(setter: delegate)
        let swizzledSelector = #selector(cio_swizzle_setDelegate(delegate:))

        let originalMethod = class_getInstanceMethod(type(of: self), originalSelector)!
        let swizzledMethod = class_getInstanceMethod(type(of: self), swizzledSelector)!

        let didAddMethod = class_addMethod(type(of: self), originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))

        if didAddMethod {
            class_replaceMethod(type(of: self), swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }

    // gets called when a new delegate gets set.
    @objc func cio_swizzle_setDelegate(delegate: UNUserNotificationCenterDelegate?) {
        guard let delegate = delegate else {
            cio_swizzle_setDelegate(delegate: delegate) // continue swizzle
            return
        }

        CustomerIOUserNotificationCenterDelegate.shared.setupSwizzling(delegate: delegate)

        // continue swizzle
        cio_swizzle_setDelegate(delegate: delegate)
    }
}

@available(iOSApplicationExtension, unavailable)
public extension MessagingPush {
    static func setupCioPushClickHandling() {
        CustomerIOUserNotificationCenterDelegate.setupCioPushClickHandling()
    }
}

// https://nshipster.com/swift-objc-runtime/
// https://github.com/expo/expo/blob/ad56550cff90602645f215d5eebd53e59fe2df76/packages/expo-dev-launcher/ios/EXDevLauncherUtils.swift#L9-L24
func swizzle(forClass: AnyClass, original: Selector, new: Selector) {
    guard let originalMethod = class_getInstanceMethod(forClass, original) else { return }
    guard let swizzledMethod = class_getInstanceMethod(forClass, new) else { return }

    let didAddMethod = class_addMethod(forClass, original, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))

    if didAddMethod {
        class_replaceMethod(forClass, new, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

// https://github.com/OneSignal/OneSignal-iOS-SDK/blob/5ac5927fca8361a3af9cee1262ac11fd49e218ee/iOS_SDK/OneSignalSDK/OneSignalCore/Source/Swizzling/OneSignalSelectorHelpers.m#L33
func swizzle(targetClass: AnyClass, targetSelector: Selector, myClass: AnyClass, mySelector: Selector) {
    // TODO: make this runtime safe.
    guard let newMethod = class_getInstanceMethod(myClass, mySelector) else {
        fatalError()
//        return
    }
    let newImplementation = method_getImplementation(newMethod)

    let methodTypeEncoding = method_getTypeEncoding(newMethod)

    let existingMethod = class_getInstanceMethod(targetClass, targetSelector)
    if existingMethod != nil {
        guard let originalMethod = class_getInstanceMethod(targetClass, targetSelector) else {
            fatalError()
//            return
        }
        let originalImplementation = method_getImplementation(originalMethod)

        guard newImplementation != originalImplementation else {
            fatalError()
//            return
        }

        class_addMethod(targetClass, mySelector, newImplementation, methodTypeEncoding)
        let newMethod = class_getInstanceMethod(targetClass, mySelector)
        method_exchangeImplementations(originalMethod, newMethod!)
    } else {
        class_addMethod(targetClass, targetSelector, newImplementation, methodTypeEncoding)
    }
}
