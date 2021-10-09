import Foundation
#if canImport(UIKit)
import UIKit

public extension CustomerIOImplementation {
    func setupScreenViewTracking() {
        let selector1 = #selector(UIViewController.viewDidAppear(_:))
        let selector2 = #selector(CustomerIOImplementation._swizzled_UIKit_viewDidAppear(_:))
        let originalMethod = class_getInstanceMethod(UIViewController.self, selector1)!
        let swizzleMethod = class_getInstanceMethod(UIViewController.self, selector2)!
        method_exchangeImplementations(originalMethod, swizzleMethod)
    }

    @objc dynamic func _swizzled_UIKit_viewDidAppear(_ animated: Bool) {
        _swizzled_UIKit_viewDidAppear(animated)

        guard let delegate = UIApplication.shared.delegate else {
            return
        }

        guard let window = delegate.window else {
            return
        }

        var viewController = window!.rootViewController
        if viewController is UINavigationController {
            viewController = (viewController as! UINavigationController).visibleViewController
        }

        var name = String(describing: type(of: viewController)).replacingOccurrences(of: "ViewController", with: "")

        if name.isEmpty || name == "" {
            if viewController?.title != nil {
                name = viewController?.title ?? "Unknown"
            }
            if name.isEmpty || name == "" {
                // Could not infer screen name
                name = "Unknown"
            }
        }

        screen(name: name, data: ScreenViewBody()) { result in
            print(result)
        }
    }
}

#endif
