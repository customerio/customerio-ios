import CioInternalCommon
import Foundation
#if canImport(UIKit)
import UIKit

// screen view tracking is not available for notification service extension. disable all functions having to deal with
// screen view tracking feature.
@available(iOSApplicationExtension, unavailable)
extension CustomerIO {
    func setupAutoScreenviewTracking() {
        swizzle(
            forClass: UIViewController.self,
            original: #selector(UIViewController.viewDidAppear(_:)),
            new: #selector(UIViewController.cio_swizzled_UIKit_viewDidAppear(_:))
        )
        swizzle(
            forClass: UIViewController.self,
            original: #selector(UIViewController.viewDidDisappear(_:)),
            new: #selector(UIViewController.cio_swizzled_UIKit_viewDidDisappear(_:))
        )
    }

    private func swizzle(forClass: AnyClass, original: Selector, new: Selector) {
        guard let originalMethod = class_getInstanceMethod(forClass, original) else { return }
        guard let swizzledMethod = class_getInstanceMethod(forClass, new) else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

// screen view tracking is not available for notification service extension. disable all functions having to deal with
// screen view tracking feature.
@available(iOSApplicationExtension, unavailable)
extension UIViewController {
    var defaultScreenViewBody: ScreenViewData {
        ScreenViewData()
    }

    @objc func cio_swizzled_UIKit_viewDidAppear(_ animated: Bool) {
        performScreenTracking()

        // this function looks like recursion, but it's how you call ViewController.viewDidAppear.
        cio_swizzled_UIKit_viewDidAppear(animated)
    }

    // capture the screen we are at when the previous ViewController got removed from the view stack.
    @objc func cio_swizzled_UIKit_viewDidDisappear(_ animated: Bool) {
        // this function looks like recursion, but it's how you call ViewController.viewDidDisappear.
        cio_swizzled_UIKit_viewDidDisappear(animated)

        performScreenTracking()
    }

    func performScreenTracking() {
        guard let diGraph = SdkInitializedUtilImpl().postInitializedData?.diGraph else {
            return // SDK not initialized yet. Therefore, we ignore event.
        }

        var rootViewController = viewIfLoaded?.window?.rootViewController
        if rootViewController == nil {
            rootViewController = getActiveRootViewController()
        }
        guard let viewController = getVisibleViewController(fromRootViewController: rootViewController) else {
            return
        }
        let nameOfViewControllerClass = String(describing: type(of: viewController))

        var name = nameOfViewControllerClass.replacingOccurrences(
            of: "ViewController",
            with: "",
            options: .caseInsensitive
        )
        if name.isEmpty || name == "" {
            if let title = viewController.title {
                name = title
            } else {
                // XXX: we couldn't infer a name, we should log it for debug purposes
                return
            }
        }

        // Before we track event, apply a filter to remove events that could be unhelpful.
        let customerOverridenFilter = diGraph.sdkConfig.filterAutoScreenViewEvents
        guard shouldTrackAutomaticScreenviewEvent(overrideFilter: customerOverridenFilter) else {
            let isUsingSdkDefaultFilter = customerOverridenFilter == nil
            diGraph.logger.debug("Automatic screenview event, \(name), was filtered out. is using sdk default filter: \(isUsingSdkDefaultFilter)")

            return // event has been filtered out. Ignore it.
        }

        guard let data = CustomerIOImplementation.autoScreenViewBody?() else {
            CustomerIO.shared.automaticScreenView(name: name, data: defaultScreenViewBody)
            return
        }
        CustomerIO.shared.automaticScreenView(name: name, data: data)
    }

    func shouldTrackAutomaticScreenviewEvent(overrideFilter: ((UIViewController) -> Bool)?) -> Bool {
        // Either get the filter provided by customer, or the SDK's default filter.
        let filter: (UIViewController) -> Bool = overrideFilter ?? { viewController in
            let isViewFromApple = viewController.bundleIdOfView?.hasPrefix("com.apple") ?? false

            if isViewFromApple {
                return false // filter out events that come from Apple's frameworks. We consider those irrelevant for customers.
            }

            // Views from customer's app or 3rd party SDKs are considered relevant and are tracked.
            return true
        }

        let shouldTrackEvent = filter(self)

        return shouldTrackEvent
    }

    /**
     Finds the top most view controller in the navigation controller/ tab bar controller stack or if it is presented
     */
    private func getVisibleViewController(fromRootViewController rootViewController: UIViewController?)
        -> UIViewController? {
        if let navigationController = rootViewController as? UINavigationController {
            return getVisibleViewController(fromRootViewController: navigationController.visibleViewController)
        }
        if let tabController = rootViewController as? UITabBarController {
            if let selected = tabController.selectedViewController {
                return getVisibleViewController(fromRootViewController: selected)
            }
        }
        if let presented = rootViewController?.presentedViewController {
            return getVisibleViewController(fromRootViewController: presented)
        }
        return rootViewController
    }

    /**
     Finds out the active root view controller by checking whether the app uses window via AppDelegate or SceneDelegate

     - returns: If window is not found then this function returns nil else returns the root view controller
     */
    private func getActiveRootViewController() -> UIViewController? {
        if let viewController = UIApplication.shared.delegate?.window??.rootViewController {
            return viewController
        } else if #available(iOS 13.0, *) {
            for scene in UIApplication.shared.connectedScenes {
                if scene.activationState == .foregroundActive, let windowScene = scene as? UIWindowScene {
                    if let sceneDelegate = windowScene.delegate as? UIWindowSceneDelegate {
                        if let sceneWindow = sceneDelegate.window {
                            return sceneWindow?.rootViewController
                        }
                    }
                }
            }
        } else { // keyWindow is deprecated in iOS 13.0*
            return UIApplication.shared.keyWindow?.rootViewController
        }

        return nil
    }
}

#else
extension CustomerIOImplementation {
    func setupAutoScreenviewTracking() {
        // XXX: log warning that tracking is not available
    }
}
#endif
