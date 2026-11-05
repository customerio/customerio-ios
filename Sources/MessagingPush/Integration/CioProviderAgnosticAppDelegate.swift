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
    private let remoteNotificationRelay: RemoteNotificationRelay
    /// Reads Info.plist `UIBackgroundModes`. Tests replace it.
    var readBackgroundModes: () -> Any? = { Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") }

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
        self.remoteNotificationRelay = RemoteNotificationRelay(appDelegate: appDelegate)
        super.init()
    }

    open func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        MessagingPush.appDelegateIntegratedExplicitly = true

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
        if aSelector == RemoteNotificationRelay.selector {
            return super.responds(to: aSelector) || takesRemoteNotifications
        }
        if implementedOptionalMethods.contains(aSelector), super.responds(to: aSelector) {
            return true
        }
        return wrappedAppDelegate?.responds(to: aSelector) ?? false
    }

    @objc
    override public func forwardingTarget(for aSelector: Selector!) -> Any? {
        if aSelector == RemoteNotificationRelay.selector {
            return takesRemoteNotifications ? remoteNotificationRelay : nil
        }
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

/// Remote notifications, silent pushes included, reach the app delegate through
/// `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`. This class has no method of its own for it,
/// so SDKs that proxy the app delegate, such as Firebase's, treat it as they always have. `forwardingTarget(for:)`
/// hands the call to `RemoteNotificationRelay` instead, which records a Customer.io silent push's Delivered receipt
/// and then calls the wrapped app delegate.
@available(iOSApplicationExtension, unavailable)
extension CioProviderAgnosticAppDelegate {
    /// Whether to take remote notifications from UIKit: the wrapped app delegate handles them, or the app has the
    /// Remote notifications background mode, so a silent push still gets its receipt.
    private var takesRemoteNotifications: Bool {
        if wrappedAppDelegate?.responds(to: RemoteNotificationRelay.selector) == true {
            return true
        }
        // UIKit calls this older callback only when the delegate lacks the newer one.
        if wrappedAppDelegate?.responds(to: RemoteNotificationRelay.olderSelector) == true {
            return false
        }
        return (readBackgroundModes() as? [String])?.contains("remote-notification") == true
    }
}

/// Records a Customer.io silent push's Delivered receipt, then passes the call to the app delegate unchanged.
@available(iOSApplicationExtension, unavailable)
private final class RemoteNotificationRelay: NSObject, UIApplicationDelegate {
    static let selector = #selector(UIApplicationDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:))
    static let olderSelector = NSSelectorFromString("application:didReceiveRemoteNotification:")

    /// The wrapper holds the app delegate.
    private weak var appDelegate: UIApplicationDelegate?

    init(appDelegate: UIApplicationDelegate?) {
        self.appDelegate = appDelegate
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        MessagingPush.recordBackgroundPush(userInfo: userInfo)
        let forwarded: Void? = appDelegate?.application?(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
        if forwarded == nil {
            completionHandler(.noData)
        }
    }
}
