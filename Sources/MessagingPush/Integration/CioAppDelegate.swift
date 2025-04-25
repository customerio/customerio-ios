import CioInternalCommon
import UIKit

public typealias CioAppDelegateType = NSObject & UIApplicationDelegate

public typealias UserNotificationCenterInstance = () -> UserNotificationCenterIntegration

// sourcery: AutoMockable
public protocol UserNotificationCenterIntegration {
    var delegate: UNUserNotificationCenterDelegate? { get set }
}

extension UNUserNotificationCenter: UserNotificationCenterIntegration {}

private extension UIApplication {
    func cioRegisterForRemoteNotifications(logger: Logger) {
        logger.debug("CIO: Registering for remote notifications")
        self.registerForRemoteNotifications()
    }
}

@available(iOSApplicationExtension, unavailable)
open class CioAppDelegate: CioAppDelegateType, UNUserNotificationCenterDelegate {
    @_spi(Internal) public let messagingPush: MessagingPushInstance
    @_spi(Internal) public let logger: Logger
    @_spi(Internal) public var implementedOptionalMethods: Set<Selector> = [
        // UIApplicationDelegate
        #selector(UIApplicationDelegate.application(_:didFinishLaunchingWithOptions:)),
        #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)),
        #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:)),
        #selector(UIApplicationDelegate.application(_:continue:restorationHandler:)),
        // UNUserNotificationCenterDelegate
        #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:)),
        #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)),
        #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:openSettingsFor:))
    ]

    private var userNotificationCenter: UserNotificationCenterInstance?
    private let wrappedAppDelegate: UIApplicationDelegate?
    private var wrappedNoticeCenterDelegate: UNUserNotificationCenterDelegate?

    // Flag to control whether to set the UNUserNotificationCenter delegate
    open var shouldIntegrateWithNotificationCenter: Bool {
        true
    }

    override public convenience init() {
        DIGraphShared.shared.logger.error("CIO: This no-argument AppDelegate initializer is not intended to be used. Added for compatibility.")
        self.init(
            messagingPush: MessagingPush.shared,
            userNotificationCenter: { UNUserNotificationCenter.current() },
            appDelegate: nil,
            logger: DIGraphShared.shared.logger
        )
    }

    public init(
        messagingPush: MessagingPushInstance,
        userNotificationCenter: UserNotificationCenterInstance?,
        appDelegate: CioAppDelegateType? = nil,
        logger: Logger
    ) {
        self.messagingPush = messagingPush
        self.userNotificationCenter = userNotificationCenter
        self.logger = logger
        self.wrappedAppDelegate = appDelegate
        super.init()
    }

    open func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let result = wrappedAppDelegate?.application?(application, didFinishLaunchingWithOptions: launchOptions)

        guard !isConfigInConflict() else {
            logger.error("CIO: Configuration in conflict. Push notifications will not work properly.")
            return true
        }

        application.cioRegisterForRemoteNotifications(logger: logger)

        if shouldIntegrateWithNotificationCenter,
           var center = userNotificationCenter?() {
            wrappedNoticeCenterDelegate = center.delegate
            center.delegate = self
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

        logger.error("CIO: Device token is deleted for current user. Failed to register for remote notifications: \(error.localizedDescription)")
        messagingPush.deleteDeviceToken()
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Function called when a push notification is clicked or swiped away.
    open func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        _ = messagingPush.userNotificationCenter(center, didReceive: response)

        if let wrappedNoticeCenterDelegate = wrappedNoticeCenterDelegate,
           wrappedNoticeCenterDelegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))) {
            wrappedNoticeCenterDelegate.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
        } else {
            completionHandler()
        }
    }

    // MARK: - method forwarding

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

    // MARK: - Private methods

    private func isConfigInConflict() -> Bool {
        guard let config = messagingPush.getConfiguration() else {
            logger.error("CIO: Missing configuration")
            return true
        }

        guard config.autoFetchDeviceToken == false else {
            logger.error("CIO: 'autoFetchDeviceToken' flag can't be enabled if AppDelegate is used")
            return true
        }

        guard config.autoTrackPushEvents == false || shouldIntegrateWithNotificationCenter == false else {
            logger.error("CIO: 'autoTrackPushEvents' flag can't be enabled if AppDelegate is used with 'shouldIntegrateWithNotificationCenter' flag set to true.")
            return true
        }

        return false
    }
}

/// Prevent issues caused by swizzling in various SDKs:
/// - those are not using `responds(to:)` and `forwardingTarget(for:)`,  but only check does original implementation exist
///     - this is the case with FirebaseMassaging
/// - for this reason, empty methods are added and forwarding to wrapper is possible
@available(iOSApplicationExtension, unavailable)
extension CioAppDelegate {
    open func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        wrappedNoticeCenterDelegate?.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
    }

    open func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        wrappedNoticeCenterDelegate?.userNotificationCenter?(center, openSettingsFor: notification)
    }

    @objc
    open func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([any UIUserActivityRestoring]?) -> Void) -> Bool {
        wrappedAppDelegate?.application?(application, continue: userActivity, restorationHandler: restorationHandler) ?? false
    }
}
