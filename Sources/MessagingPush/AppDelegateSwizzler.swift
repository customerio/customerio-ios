import Foundation
import UIKit

public protocol AppDelegateSwizzlerDelegate: AnyObject {
    func didReceiveAPNSToken(_ deviceToken: Data)
}

public typealias RegisterForNotificationsClosureType = @convention(c) (AnyObject, Selector, UIApplication, Data) -> Void

@available(iOSApplicationExtension, unavailable)
public class AppDelegateSwizzler {
    private static let shared = AppDelegateSwizzler()
    private weak var delegate: AppDelegateSwizzlerDelegate?
    private static var registerForNotificationsOriginalImp: RegisterForNotificationsClosureType?

    public class func startSwizzlingIfPossible(_ delegate: AppDelegateSwizzlerDelegate) {
        shared.delegate = delegate
    }

    private init() {
        guard
            let originalClass = object_getClass(UIApplication.shared.delegate),
            let swizzledClass = object_getClass(self)
        else { return }

        let originalSelector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        let swizzledSelector = #selector(swizzled_application(_:didRegisterForRemoteNotificationsWithDeviceToken:))

        swizzle(originalClass, swizzledClass, originalSelector, swizzledSelector)
    }

    private func swizzle(_ originalClass: AnyClass, _ swizzledClass: AnyClass, _ originalSelector: Selector, _ swizzledSelector: Selector) {
        guard let swizzledMethod = class_getInstanceMethod(swizzledClass, swizzledSelector) else {
            return
        }

        if let originalMethod = class_getInstanceMethod(originalClass, originalSelector) {
            print("we did the swizzle. \(String(describing: originalClass)) \(String(describing: originalSelector)) \(String(describing: swizzledClass)) \(String(describing: swizzledSelector))")

            let imp = method_getImplementation(originalMethod)
            AppDelegateSwizzler.registerForNotificationsOriginalImp = unsafeBitCast(imp, to: RegisterForNotificationsClosureType.self)

            // exchange implementation
            method_exchangeImplementations(originalMethod, swizzledMethod)
        } else {
            // add implementation
            class_addMethod(originalClass, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))
        }
    }

    @objc private func swizzled_application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // call parent method
        AppDelegateSwizzler.registerForNotificationsOriginalImp?(UIApplication.shared.delegate!, #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)), application, deviceToken)

        Self.shared.delegate?.didReceiveAPNSToken(deviceToken)
    }
}
