import Foundation
import UserNotifications

@available(iOSApplicationExtension, unavailable)
public class CustomerIOUserNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = CustomerIOUserNotificationCenterDelegate()

    override private init() {}

    @objc open weak var delegate: UNUserNotificationCenterDelegate? {
        set {
            print("setDelegate is called.se")

            //  self.delegate = delegate // continue swizzle
        }
        get {
            UNUserNotificationCenter.current().delegate
        }
    }

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

    private let notificationCenterDelegateClasses = NSMutableSet()

    // Notification was interacted with.
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        _ = MessagingPush.shared.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }

    @objc func cio_swizzle_UNUserNotificationCenter_setDelegate(_ delegate: UNUserNotificationCenterDelegate) {
        let classForDelegate: AnyClass = type(of: delegate)

        // TODO: make sure that we only setup swizzling 1 time on this class.
        // https://github.com/OneSignal/OneSignal-iOS-SDK/blob/main/iOS_SDK/OneSignalSDK/OneSignalNotifications/Categories/UNUserNotificationCenter%2BOneSignalNotifications.m#L186
        notificationCenterDelegateClasses.add(classForDelegate)

        swizzle(
            targetClass: classForDelegate,
            targetSelector: #selector(userNotificationCenter(_:didReceive:withCompletionHandler:)),
            myClass: CustomerIOUserNotificationCenterDelegate.self,
            mySelector: #selector(cio_swizzle_didReceive(_:didReceive:withCompletionHandler:))
        )

        // continue
        cio_swizzle_UNUserNotificationCenter_setDelegate(delegate)
    }

    @objc func cio_swizzle_didReceive(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        _ = MessagingPush.shared.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)

        // continue
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

    func cioSetupDelegateSwizzling(delegate: UNUserNotificationCenterDelegate) {
        swizzle(
            targetClass: type(of: delegate),
            targetSelector: #selector(delegate.userNotificationCenter(_:didReceive:withCompletionHandler:)),
            myClass: UNUserNotificationCenter.self,
            mySelector: #selector(cio_swizzle_didReceive(_:didReceive:withCompletionHandler:))
        )
    }

    @objc func cio_swizzle_didReceive(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        print("cio_swizzle_didReceive is called.")

        _ = MessagingPush.shared.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)

        // continue
        cio_swizzle_didReceive(center, didReceive: response, withCompletionHandler: completionHandler)
    }

    @objc func cio_swizzle_setDelegate(delegate: UNUserNotificationCenterDelegate?) {
        print("cio_swizzle_setDelegate is called.")

        cioSetupDelegateSwizzling(delegate: delegate!)

        // continue the path
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
