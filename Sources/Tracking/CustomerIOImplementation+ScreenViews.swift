import Foundation
#if canImport(UIKit)
import UIKit

extension CustomerIOImplementation {
    func setupAutoScreenviewTracking() {
        let selector1 = #selector(UIViewController.viewDidAppear(_:))
        let selector2 = #selector(UIViewController.cio_swizzled_UIKit_viewDidAppear(_:))
        guard let originalMethod = class_getInstanceMethod(UIViewController.self, selector1) else {
            return
        }
        guard let swizzleMethod = class_getInstanceMethod(UIViewController.self, selector2) else {
            return
        }
        method_exchangeImplementations(originalMethod, swizzleMethod)
    }
}

internal extension UIViewController {
    var defaultScreenViewBody: ScreenViewData {
        ScreenViewData()
    }

    @objc func cio_swizzled_UIKit_viewDidAppear(_ animated: Bool) {
        cio_swizzled_UIKit_viewDidAppear(animated)
        let rootViewController = activeRootViewController()
        guard let viewController = visibleViewController(rootViewController) else {
            return
        }
        let controllerString = String(describing: type(of: viewController))
        var name = controllerString.replacingOccurrences(of: "ViewController", with: "", options: .caseInsensitive)
        if name.isEmpty || name == "" {
            if let title = viewController.title {
                name = title
            }
            if name.isEmpty || name == "" {
                // XXX: we couldn't infer a name, we should log it for debug purposes
                return
            }
        }
        guard let data = CustomerIOImplementation.autoScreenViewBody?() else {
            CustomerIO.shared.automaticScreenView(name: name, data: defaultScreenViewBody)
            return
        }
        CustomerIO.shared.automaticScreenView(name: name, data: data)
    }

    /**
     Finds the top most view controller in the navigation controller/ tab bar controller stack or if it is presented
     */
    private func visibleViewController(_ controller: UIViewController?) -> UIViewController? {
        if let navigationController = controller as? UINavigationController {
            return visibleViewController(navigationController.visibleViewController)
        }
        if let tabController = controller as? UITabBarController {
            if let selected = tabController.selectedViewController {
                return visibleViewController(selected)
            }
        }
        if let presented = controller?.presentedViewController {
            return visibleViewController(presented)
        }
        return controller
    }

    /**
     Finds out the active root view controller by checking whether the app uses window via AppDelegate or SceneDelegate

     - returns: If window is not found then this function returns nil else returns the root view controller
     */
    private func activeRootViewController() -> UIViewController? {
        var window: UIWindow?
        if let appDelegateWindow = UIApplication.shared.delegate?.window {
            window = appDelegateWindow
        } else if #available(iOS 13.0, *) {
            for scene in UIApplication.shared.connectedScenes {
                if scene.activationState == .foregroundActive, let windowScene = scene as? UIWindowScene {
                    if let sceneDelegate = windowScene.delegate as? UIWindowSceneDelegate {
                        if let sceneWindow = sceneDelegate.window {
                            window = sceneWindow
                            break
                        }
                    }
                }
            }
        } else { // keyWindow is deprecated in iOS 13.0*
            window = UIApplication.shared.keyWindow
        }
        guard let activeWindow = window else { return nil }
        return activeWindow.rootViewController
    }
}

#else
extension CustomerIOImplementation {
    func setupAutoScreenviewTracking() {
        // XXX: log warning that tracking is not available
    }
}
#endif
