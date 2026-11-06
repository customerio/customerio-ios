import UIKit
import XCTest

extension XCTestCase {
    /// Does what Firebase's app delegate proxy (GoogleUtilities 8.1.5 and later) does: moves `object` to a new subclass
    /// whose method calls the original class's implementation or, when the class has none, `forwardingTarget(for:)`.
    func proxyLikeFirebase(_ object: NSObject) throws {
        typealias Completion = @convention(block) (UIBackgroundFetchResult) -> Void
        typealias Original = @convention(c) (AnyObject, Selector, UIApplication, NSDictionary, Completion) -> Void
        typealias Donor = @convention(block) (NSObject, UIApplication, NSDictionary, @escaping Completion) -> Void
        let selector = #selector(UIApplicationDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:))
        let realClass: AnyClass = try XCTUnwrap(object_getClass(object))
        let original = class_getInstanceMethod(realClass, selector).map(method_getImplementation)
        let donor: Donor = { delegate, application, userInfo, completion in
            if let original {
                unsafeBitCast(original, to: Original.self)(delegate, selector, application, userInfo, completion)
            } else if let target = delegate.forwardingTarget(for: selector) as? NSObject,
                      target !== delegate, target.responds(to: selector) {
                (target as? UIApplicationDelegate)?.application?(application, didReceiveRemoteNotification: userInfo as? [AnyHashable: Any] ?? [:], fetchCompletionHandler: completion)
            } else {
                completion(.noData)
            }
        }
        let proxyClass: AnyClass = try XCTUnwrap(objc_allocateClassPair(realClass, "TestProxy_\(UUID().uuidString)", 0))
        let types = protocol_getMethodDescription(UIApplicationDelegate.self, selector, false, true).types
        class_addMethod(proxyClass, selector, imp_implementationWithBlock(donor), types.map { UnsafePointer($0) })
        objc_registerClassPair(proxyClass)
        object_setClass(object, proxyClass)
    }
}
