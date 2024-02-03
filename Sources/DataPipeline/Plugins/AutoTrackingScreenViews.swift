import CioInternalCommon
import Foundation
import Segment
#if canImport(UIKit)
import UIKit
#endif

// screen view tracking is not available for notification service extension. disable all functions having to deal with
// screen view tracking feature.
@available(iOSApplicationExtension, unavailable)
public class AutoTrackingScreenViews: UtilityPlugin {
    public let type = PluginType.utility

    public var analytics: Segment.Analytics?
    public var diGraph = DIGraphShared.shared

    static let notificationName = Notification.Name(rawValue: "AutoTrackingScreenViewsNotification")
    static let screenNameKey = "name"

    #if canImport(UIKit)
    /**
     Filter automatic screenview events to remove events that are irrelevant to your app.

     Return `true` from function if you would like the screenview event to be tracked.

     Default: `nil`, which uses the default filter function packaged by the SDK. Provide a non-nil value to not call the SDK's filtering.
     */
    public var filterAutoScreenViewEvents: ((UIViewController) -> Bool)?
    #endif

    /**
     Handler to be called by our automatic screen tracker to generate `screen` event body variables. You can use
     this to override our defaults and pass custom values in the body of the `screen` event
     */
    public var autoScreenViewBody: (() -> [String: Any])?

    public init(
        filterAutoScreenViewEvents: ((UIViewController) -> Bool)? = nil,

        autoScreenViewBody: (() -> [String: Any])? = nil
    ) {
        self.filterAutoScreenViewEvents = filterAutoScreenViewEvents
        self.autoScreenViewBody = autoScreenViewBody
        setupAutoScreenviewTracking()
    }

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

@available(iOSApplicationExtension, unavailable)
extension AutoTrackingScreenViews {
    func performScreenTracking(onViewController viewController: UIViewController) {
        guard let name = viewController.getNameForAutomaticScreenViewTracking() else {
            diGraph.logger.info("Automatic screenview tracking event ignored for \(viewController). Could not determine name to use for screen.")
            return
        }

        // Before we track event, apply a filter to remove events that could be unhelpful.
        let customerOverridenFilter = filterAutoScreenViewEvents
        let defaultSdkFilter: (UIViewController) -> Bool = { viewController in
            let isViewFromApple = viewController.bundleIdOfView?.hasPrefix("com.apple") ?? false

            if isViewFromApple {
                return false // filter out events that come from Apple's frameworks. We consider those irrelevant for customers.
            }

            // Views from customer's app or 3rd party SDKs are considered relevant and are tracked.
            return true
        }

        let filter = customerOverridenFilter ?? defaultSdkFilter
        let shouldTrackEvent = filter(viewController)

        guard shouldTrackEvent else {
            let isUsingSdkDefaultFilter = customerOverridenFilter == nil
            diGraph.logger.debug("automatic screenview ignored for, \(name):\(viewController.bundleIdOfView ?? ""). It was filtered out. Is using sdk default filter: \(isUsingSdkDefaultFilter)")
            return // event has been filtered out. Ignore it.
        }

        let addionalScreenViewData = autoScreenViewBody?() ?? [:]
        analytics?.screen(title: name, properties: addionalScreenViewData)
    }
}

// screen view tracking is not available for notification service extension. disable all functions having to deal with
// screen view tracking feature.
@available(iOSApplicationExtension, unavailable)
extension UIViewController {
    @objc func cio_swizzled_UIKit_viewDidAppear(_ animated: Bool) {
        performAutomaticScreenTracking()

        // this function looks like recursion, but it's how you call ViewController.viewDidAppear.
        cio_swizzled_UIKit_viewDidAppear(animated)
    }

    // capture the screen we are at when the previous ViewController got removed from the view stack.
    @objc func cio_swizzled_UIKit_viewDidDisappear(_ animated: Bool) {
        // this function looks like recursion, but it's how you call ViewController.viewDidDisappear.
        cio_swizzled_UIKit_viewDidDisappear(animated)

        performAutomaticScreenTracking()
    }

    func performAutomaticScreenTracking() {
        var rootViewController = viewIfLoaded?.window?.rootViewController
        if rootViewController == nil {
            rootViewController = getActiveRootViewController()
        }
        guard let viewController = getVisibleViewController(fromRootViewController: rootViewController) else {
            return
        }

        // find if AutoTrackingScreenViews plugin was added, if so ask it to perform tracking
        if let screenTrackingPlugin = DataPipeline.shared.analytics.find(pluginType: AutoTrackingScreenViews.self) {
            screenTrackingPlugin.performScreenTracking(onViewController: viewController)
        }
    }

    func getNameForAutomaticScreenViewTracking() -> String? {
        let nameOfViewControllerClass = String(describing: type(of: self))

        let name = nameOfViewControllerClass.replacingOccurrences(
            of: "ViewController",
            with: "",
            options: .caseInsensitive
        )
        if !name.isEmpty {
            return name
        }

        if title != nil {
            return title
        }

        return nil
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
