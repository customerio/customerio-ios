import CioInternalCommon
import UIKit

public typealias CioAppDelegateType = NSObject & UIApplicationDelegate

public typealias ConfigInstance = () -> MessagingPushConfigOptions

public typealias UserNotificationCenterInstance = () -> UserNotificationCenterIntegration

// sourcery: AutoMockable
public protocol UserNotificationCenterIntegration {
    var delegate: UNUserNotificationCenterDelegate? { get set }
}

extension UNUserNotificationCenter: UserNotificationCenterIntegration {}

private extension UIApplication {
    func cioRegisterForRemoteNotifications(logger: Logger) {
        logger.debug("CIO: Registering for remote notifications")
        registerForRemoteNotifications()
    }
}

@available(iOSApplicationExtension, unavailable)
open class CioProviderAgnosticAppDelegate: CioAppDelegateType {
    @_spi(Internal) public let messagingPush: MessagingPushInstance
    @_spi(Internal) public let logger: Logger
    @_spi(Internal) public var implementedOptionalMethods: Set<Selector> = [
        // UIApplicationDelegate
        #selector(UIApplicationDelegate.application(_:didFinishLaunchingWithOptions:)),
        #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)),
        #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:)),
        #selector(UIApplicationDelegate.application(_:continue:restorationHandler:)),
        #selector(UIApplicationDelegate.application(_:open:options:))
    ]

    @_spi(Internal) public var config: ConfigInstance?

    private let wrappedAppDelegate: UIApplicationDelegate?

    override public convenience init() {
        DIGraphShared.shared.logger.error("CIO: This no-argument initializer should not to be used. Added since UIKit's AppDelegate initialization process crashes if for no-arg init is missing.")
        self.init(
            messagingPush: MessagingPush.shared,
            appDelegate: nil,
            config: nil,
            logger: DIGraphShared.shared.logger
        )
    }

    public init(
        messagingPush: MessagingPushInstance,
        appDelegate: CioAppDelegateType? = nil,
        config: ConfigInstance? = nil,
        logger: Logger
    ) {
        self.messagingPush = messagingPush
        self.logger = logger
        self.config = config
        self.wrappedAppDelegate = appDelegate
        super.init()
        _ = Self.remoteNotificationForwardingInstalled
    }

    open func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        MessagingPush.appDelegateIntegratedExplicitly = true
        // Before the wrapped delegate runs, as that is where apps usually configure Firebase.
        installRemoteNotificationForwarding(on: application.delegate)

        let result = wrappedAppDelegate?.application?(application, didFinishLaunchingWithOptions: launchOptions)

        if config?().autoFetchDeviceToken ?? false {
            application.cioRegisterForRemoteNotifications(logger: logger)
        }

        return result ?? true
    }

    open func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        wrappedAppDelegate?.application?(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    open func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        wrappedAppDelegate?.application?(application, didFailToRegisterForRemoteNotificationsWithError: error)

        MessagingPush.shared.didFailToRegisterForRemoteNotifications(error: error)
    }

    // MARK: - method forwarding

    @objc
    override public func conforms(to aProtocol: Protocol) -> Bool {
        super.conforms(to: aProtocol) || wrappedAppDelegate?.conforms(to: aProtocol) == true
    }

    @objc
    override public func responds(to aSelector: Selector!) -> Bool {
        if implementedOptionalMethods.contains(aSelector), super.responds(to: aSelector) {
            return true
        }
        return wrappedAppDelegate?.responds(to: aSelector) ?? false
    }

    @objc
    override public func forwardingTarget(for aSelector: Selector!) -> Any? {
        if implementedOptionalMethods.contains(aSelector), super.responds(to: aSelector) {
            return self
        }
        if let wrappedAppDelegate = wrappedAppDelegate,
           wrappedAppDelegate.responds(to: aSelector) {
            return wrappedAppDelegate
        }
        return nil
    }
}

/// Prevent issues caused by swizzling in various SDKs:
/// - those are not using `responds(to:)` and `forwardingTarget(for:)`,  but only check does original implementation exist
///     - this is the case with FirebaseMassaging
/// - for this reason, empty methods are added and forwarding to wrapper is possible
@available(iOSApplicationExtension, unavailable)
extension CioProviderAgnosticAppDelegate {
    @objc
    open func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([any UIUserActivityRestoring]?) -> Void) -> Bool {
        wrappedAppDelegate?.application?(application, continue: userActivity, restorationHandler: restorationHandler) ?? false
    }

    open func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        wrappedAppDelegate?.application?(app, open: url, options: options) ?? false
    }
}

/// Background pushes reach the app delegate through `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`.
/// SDKs that proxy the app delegate, such as Firebase's, subclass the class of `UIApplication.shared.delegate` and
/// call only what that class implements, skipping `forwardingTarget(for:)`. Without the forwarders below, the app's
/// handler never runs under such a proxy, and neither does `MessagingPush.shared.handleBackgroundPush(userInfo:)`.
///
/// Before silent push, a proxy found nothing to call here, so the app's handler didn't run under it. Some apps rely on
/// that: Flutter's `FlutterAppDelegate` would hand the push to `firebase_messaging` a second time. A call through a
/// proxy therefore reaches the app only when it turned on `backgroundPushEnabled`. UIKit's own calls always do.
@available(iOSApplicationExtension, unavailable)
extension CioProviderAgnosticAppDelegate {
    private typealias FetchCompletionHandler = @convention(block) (UIBackgroundFetchResult) -> Void

    private static let remoteNotificationSelector = #selector(UIApplicationDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:))

    private static var remoteNotificationTypeEncoding: UnsafePointer<CChar>? {
        protocol_getMethodDescription(UIApplicationDelegate.self, remoteNotificationSelector, false, true).types.map { UnsafePointer($0) }
    }

    /// Whether a proxy subclassed `object` after `installedClass` got the forwarder, and is calling it as the original.
    private static func isCalledThroughProxy(_ object: AnyObject, installedOn installedClass: AnyClass) -> Bool {
        class_getMethodImplementation(object_getClass(object), remoteNotificationSelector)
            != class_getMethodImplementation(installedClass, remoteNotificationSelector)
    }

    /// Gives this class its own implementation, forwarding to the wrapped app delegate. Added at runtime, so an app's
    /// subclass that implements the method itself keeps compiling without `override` and still runs. The selector
    /// stays out of `implementedOptionalMethods`, so `responds(to:)` answers for the wrapped delegate and UIKit
    /// calls this only when the app handles background pushes.
    static let remoteNotificationForwardingInstalled: Bool = {
        typealias Implementation = @convention(block) (CioProviderAgnosticAppDelegate, UIApplication, NSDictionary, @escaping FetchCompletionHandler) -> Void
        let implementation: Implementation = { delegate, application, userInfo, completionHandler in
            delegate.forwardRemoteNotification(
                application,
                userInfo: userInfo as? [AnyHashable: Any] ?? [:],
                throughProxy: isCalledThroughProxy(delegate, installedOn: CioProviderAgnosticAppDelegate.self),
                completionHandler: completionHandler
            )
        }
        return class_addMethod(CioProviderAgnosticAppDelegate.self, remoteNotificationSelector, imp_implementationWithBlock(implementation), remoteNotificationTypeEncoding)
    }()

    /// With `UIApplicationDelegateAdaptor`, `UIApplication.shared.delegate` is SwiftUI's own app delegate, which forwards
    /// the callback to this wrapper without implementing it. Gives that class a forwarder too, so a proxy created
    /// afterwards calls it. Does nothing when the app doesn't handle background pushes, or when `applicationDelegate`
    /// implements the method or is this wrapper.
    func installRemoteNotificationForwarding(on applicationDelegate: UIApplicationDelegate?) {
        let selector = Self.remoteNotificationSelector
        guard let applicationDelegate = applicationDelegate as? NSObject, applicationDelegate !== self,
              applicationDelegate.forwardingTarget(for: selector) as AnyObject? === self,
              let delegateClass = object_getClass(applicationDelegate),
              class_getInstanceMethod(delegateClass, selector) == nil
        else { return }

        typealias Implementation = @convention(block) (NSObject, UIApplication, NSDictionary, @escaping FetchCompletionHandler) -> Void
        let implementation: Implementation = { delegate, application, userInfo, completionHandler in
            guard let wrapper = delegate.forwardingTarget(for: selector) as? CioProviderAgnosticAppDelegate else {
                return completionHandler(.noData)
            }
            wrapper.forwardRemoteNotification(
                application,
                userInfo: userInfo as? [AnyHashable: Any] ?? [:],
                throughProxy: Self.isCalledThroughProxy(delegate, installedOn: delegateClass),
                completionHandler: completionHandler
            )
        }
        class_addMethod(delegateClass, selector, imp_implementationWithBlock(implementation), Self.remoteNotificationTypeEncoding)
    }

    private func forwardRemoteNotification(
        _ application: UIApplication,
        userInfo: [AnyHashable: Any],
        throughProxy: Bool,
        completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard !throughProxy || config?().backgroundPushEnabled == true else {
            return completionHandler(.noData)
        }
        let forwarded: Void? = wrappedAppDelegate?.application?(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
        if forwarded == nil {
            // Called although the wrapped delegate doesn't handle it; iOS still needs the handler called.
            completionHandler(.noData)
        }
    }
}
