import Foundation
#if canImport(UIKit)
import UIKit

public extension CustomerIOImplementation {
    func setupAutoScreenviewTracking() {
        let selector1 = #selector(UIViewController.viewDidAppear(_:))
        let selector2 = #selector(CustomerIOImplementation._swizzled_UIKit_viewDidAppear(_:))
        guard let originalMethod = class_getInstanceMethod(UIViewController.self, selector1) else {
            return
        }
        guard let swizzleMethod = class_getInstanceMethod(CustomerIOImplementation.self, selector2) else {
            return
        }
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

        var viewController = window.rootViewController
        if let navigationController = viewController as? UINavigationController {
            viewController = navigationController.visibleViewController
        }

        var name = String(describing: type(of: viewController)).replacingOccurrences(of: "ViewController", with: "")

        if name.isEmpty || name == "" {
            if let title = viewController?.title {
                name = title
            }
            if name.isEmpty || name == "" {
                return
            }
        }

        let data = autoScreenViewBody?() ?? ScreenViewData(data: ScreenViewDefaultData())

        screen(name: name, data: data) { _ in
            // XXX: global error handling of result here
        }
    }
}

#else
public extension CustomerIOImplementation {
    func setupAutoScreenviewTracking() {
        // XXX: log warning that tracking is not available
    }
}
#endif
