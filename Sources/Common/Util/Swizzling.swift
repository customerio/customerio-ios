import Foundation

/**
 General tips when swizzling:

 1. The Swift functdion that you want to have called in your code base should have this basic function signiture:
 ```
 @objc dynamic func ....
 ```
 Without these important keywords, your swizzled function may not get called at runtime.

 2. Inside of your swizzled function, be sure to "continue" the swizzle. Example:
 ```
 @objc dynamic func cio_swizzled_viewDidLoad() {
   // perform some logic in the SDK when the view loaded.

   self.cio_swizzled_viewDidLoad() // continue swizzle
 }
 ```

 This looks like recursion, but what it actually is doing is performing a call to the original function that you replaced by swizzling. If you forget to do this, there is a chance that code in a customer's app or another 3rd party SDK will not perform correctly.
 */

public func swizzle(forClass: AnyClass, original: Selector, new: Selector) {
    guard let originalMethod = class_getInstanceMethod(forClass, original) else { return }
    guard let swizzledMethod = class_getInstanceMethod(forClass, new) else { return }

    let didAddMethod = class_addMethod(forClass, original, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))

    if didAddMethod {
        class_replaceMethod(forClass, new, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

public func swizzle(targetClass: AnyClass, targetSelector: Selector, myClass: AnyClass, mySelector: Selector) {
    guard let newMethod = class_getInstanceMethod(myClass, mySelector) else {
        return
    }
    let newImplementation = method_getImplementation(newMethod)

    let methodTypeEncoding = method_getTypeEncoding(newMethod)

    let existingMethod = class_getInstanceMethod(targetClass, targetSelector)
    if existingMethod != nil {
        guard let originalMethod = class_getInstanceMethod(targetClass, targetSelector) else {
            return
        }
        let originalImplementation = method_getImplementation(originalMethod)

        guard newImplementation != originalImplementation else {
            return
        }

        class_addMethod(targetClass, mySelector, newImplementation, methodTypeEncoding)
        let newMethod = class_getInstanceMethod(targetClass, mySelector)
        method_exchangeImplementations(originalMethod, newMethod!)
    } else {
        class_addMethod(targetClass, targetSelector, newImplementation, methodTypeEncoding)
    }
}
