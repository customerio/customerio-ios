import Foundation
#if canImport(UIKit)
import UIKit

public extension UIApplication {
    func open(url: URL) {
        open(url, options: [:]) { _ in }
    }
}

public extension UIViewController {
    static func swizzleScreenViews(customerIO: CustomerIO) {
        let selector1 = #selector(UIViewController.viewDidAppear(_:))
        let selector2 = #selector(UIViewController._swizzled_viewDidAppear(_:))
        let originalMethod = class_getInstanceMethod(UIViewController.self, selector1)!
        let swizzleMethod = class_getInstanceMethod(UIViewController.self, selector2)!
        method_exchangeImplementations(originalMethod, swizzleMethod)
    }

    @objc dynamic func _swizzled_viewDidAppear(_ animated: Bool) {
        _swizzled_viewDidAppear(animated)

        // XXX: how best to pass through the customerIO instance
        // XXX: switch to screen view when available
        CustomerIO.shared.track(name: "screen_view") { result in
            print(result)
        }
    }
}
#endif
