import Foundation
import UIKit

public protocol AppDelegateSwizzlerDelegate: AnyObject {
    func didReceiveAPNSToken(_ deviceToken: Data)
}

// Type alias for the original method's implementation
public typealias RegisterForNotificationsClosureType = @convention(c) (AnyObject, Selector, UIApplication, Data) -> Void

@available(iOSApplicationExtension, unavailable)
public class AppDelegateSwizzler {
    private static let shared = AppDelegateSwizzler()
    private weak var delegate: AppDelegateSwizzlerDelegate?

    // Stores the original implementation of the method that our SDK replaces with swizzling.
    // By storing the original implementation, we can call it from our swizzled method.
    // This allows us to add our custom logic to the method without losing the original functionality.
    private static var registerForNotificationsOriginalImp: RegisterForNotificationsClosureType?

    // Method to start swizzling and set the delegate
    public class func startSwizzling(_ delegate: AppDelegateSwizzlerDelegate) {
        shared.delegate = delegate
    }

    // Setup the swizzling code, just once, by putting in constructor.
    private init() {
        guard
            let originalClass = object_getClass(UIApplication.shared.delegate),
            let swizzledClass = object_getClass(self)
        else { return }

        // Selectors for the original and swizzled methods
        let originalSelector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        let swizzledSelector = #selector(swizzled_application(_:didRegisterForRemoteNotificationsWithDeviceToken:))

        // Perform the swizzling
        swizzle(originalClass, swizzledClass, originalSelector, swizzledSelector)
    }

    // Method to perform the swizzling
    private func swizzle(_ originalClass: AnyClass, _ swizzledClass: AnyClass, _ originalSelector: Selector, _ swizzledSelector: Selector) {
        guard let swizzledMethod = class_getInstanceMethod(swizzledClass, swizzledSelector) else {
            return
        }

        // Check if the original method exists
        if let originalMethod = class_getInstanceMethod(originalClass, originalSelector) {
            // Get the implementation of the original method
            let imp = method_getImplementation(originalMethod)
            // Store the original implementation in the static variable
            // Due to the nature of how `IMP` works and the need to cast it to a specific function pointer type, `unsafeBitCast` is necessary to cast the `IMP` to the correct function pointer type because Swift does not support direct casting between arbitrary pointer types and function types.
            // This ensures that the cast is performed correctly and safely within the constraints of Swift's type system.
            AppDelegateSwizzler.registerForNotificationsOriginalImp = unsafeBitCast(imp, to: RegisterForNotificationsClosureType.self)

            // Exchange the implementations of the original and swizzled methods
            method_exchangeImplementations(originalMethod, swizzledMethod)
        } else {
            // Add the swizzled method if the original method does not exist
            class_addMethod(originalClass, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))
        }
    }

    // Swizzled method implementation. This function gets called instead of the original method in the app.
    @objc private func swizzled_application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Perform the custom logic in our SDK when a APN device token is registered to the app!
        Self.shared.delegate?.didReceiveAPNSToken(deviceToken)

        // Call the original method using the stored implementation. This ensures the original functionality of the customer's app is not lost.
        AppDelegateSwizzler.registerForNotificationsOriginalImp?(UIApplication.shared.delegate!, #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)), application, deviceToken)
    }
}
