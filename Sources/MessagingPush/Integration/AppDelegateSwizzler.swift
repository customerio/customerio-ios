import ObjectiveC
import UIKit

/// Adds Customer.io handlers to the app delegate's remote notification registration callbacks, for apps that don't use
/// `CioAppDelegateWrapper`. The app delegate keeps what it already did for each callback, whether it implements it,
/// inherits it or forwards it: that runs first and the handler runs after it, the same order as the wrapper.
@_spi(Internal)
@available(iOSApplicationExtension, unavailable)
public enum AppDelegateSwizzler {
    private typealias Implementation = @convention(c) (AnyObject, Selector, UIApplication, AnyObject?) -> Void

    private struct SwizzledMethod: Hashable {
        let delegateClass: ObjectIdentifier
        let selector: Selector
    }

    private static let lock = NSLock()
    private static var swizzledMethods: Set<SwizzledMethod> = []

    /// Runs `handler` with the APNs device token after the app delegate's own `didRegisterForRemoteNotificationsWithDeviceToken`.
    /// Safe to call more than once for the same app delegate.
    public static func swizzleDidRegisterForRemoteNotifications(
        of appDelegate: UIApplicationDelegate?,
        handler: @escaping (UIApplication, Data) -> Void
    ) {
        let selector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        swizzle(selector, of: appDelegate) { application, deviceToken in
            guard let deviceToken = deviceToken as? Data else { return }
            handler(application, deviceToken)
        }
    }

    /// Runs `handler` with the error after the app delegate's own `didFailToRegisterForRemoteNotificationsWithError`.
    /// Safe to call more than once for the same app delegate.
    public static func swizzleDidFailToRegisterForRemoteNotifications(
        of appDelegate: UIApplicationDelegate?,
        handler: @escaping (UIApplication, Error) -> Void
    ) {
        let selector = #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:))
        swizzle(selector, of: appDelegate) { application, error in
            guard let error = error as? Error else { return }
            handler(application, error)
        }
    }

    private static func swizzle(_ selector: Selector, of appDelegate: UIApplicationDelegate?, handler: @escaping (UIApplication, AnyObject?) -> Void) {
        guard let appDelegate, let delegateClass = object_getClass(appDelegate) else { return }
        // The wrapper already runs the handlers and forwards to the app's delegate, also when SwiftUI's delegate forwards to it.
        guard !(appDelegate is CioProviderAgnosticAppDelegate),
              !(forwardingTarget(of: appDelegate, for: selector) is CioProviderAgnosticAppDelegate)
        else { return }

        lock.lock()
        defer { lock.unlock() }

        // Swizzling again would run the handler twice. A superclass counts too: an isa-swizzling SDK such as Firebase's
        // app delegate proxy can subclass the app delegate after the first swizzle, and its subclass calls ours.
        var classInHierarchy: AnyClass? = delegateClass
        while let swizzledClass = classInHierarchy {
            if swizzledMethods.contains(SwizzledMethod(delegateClass: ObjectIdentifier(swizzledClass), selector: selector)) { return }
            classInHierarchy = class_getSuperclass(swizzledClass)
        }
        swizzledMethods.insert(SwizzledMethod(delegateClass: ObjectIdentifier(delegateClass), selector: selector))

        // An inherited implementation is called, never replaced, so other subclasses of the superclass are left alone.
        let existingMethod = class_getInstanceMethod(delegateClass, selector)
        let original = existingMethod.map(method_getImplementation)
        let typeEncoding = existingMethod.flatMap(method_getTypeEncoding)
            ?? UnsafePointer(protocol_getMethodDescription(UIApplicationDelegate.self, selector, false, true).types)

        let implementation: @convention(block) (AnyObject, UIApplication, AnyObject?) -> Void = { delegate, application, argument in
            if let original {
                unsafeBitCast(original, to: Implementation.self)(delegate, selector, application, argument)
            } else if let target = forwardingTarget(of: delegate, for: selector),
                      let targetImplementation = class_getMethodImplementation(object_getClass(target), selector) {
                // Adding the method stopped the runtime from forwarding the callback, so forward it here.
                unsafeBitCast(targetImplementation, to: Implementation.self)(target, selector, application, argument)
            }
            handler(application, argument)
        }
        class_replaceMethod(delegateClass, selector, imp_implementationWithBlock(implementation), typeEncoding)
    }

    /// Where a delegate that doesn't implement `selector` forwards it, like SwiftUI's app delegate does to the
    /// `UIApplicationDelegateAdaptor` delegate.
    private static func forwardingTarget(of delegate: AnyObject, for selector: Selector) -> AnyObject? {
        guard let forwarded = (delegate as? NSObject)?.forwardingTarget(for: selector) else { return nil }
        let target = forwarded as AnyObject
        guard target !== delegate, (target as? NSObjectProtocol)?.responds(to: selector) == true else { return nil }
        return target
    }
}
