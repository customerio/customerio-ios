import UIKit
import CioInternalCommon

public typealias AppDelegateType = NSObject & UIApplicationDelegate

@available(iOSApplicationExtension, unavailable)
open class AppDelegate: AppDelegateType, UNUserNotificationCenterDelegate {
    @_spi(Internal) public let messagingPush: MessagingPush
    @_spi(Internal) public let logger: Logger
    
    private let wrappedAppDelegate: UIApplicationDelegate?
    private var wrappedNoticeCenterDelegate: UNUserNotificationCenterDelegate?

    // Flag to control whether to set the UNUserNotificationCenter delegate
    open var shouldSetNotificationCenterDelegate: Bool {
        return true
    }
    
    public override convenience init() {
        self.init(messagingPush: MessagingPush.shared, appDelegate: nil, logger: DIGraphShared.shared.logger)
    }
    
    public init(messagingPush: MessagingPush, appDelegate: AppDelegateType? = nil, logger: Logger) {
        self.messagingPush = messagingPush
        self.logger = logger
        self.wrappedAppDelegate = appDelegate
        super.init()
    }
    
    open func application(_ application: UIApplication,
                          didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let result = wrappedAppDelegate?.application?(application, didFinishLaunchingWithOptions: launchOptions)
       
        guard !isConfigInConflict() else {
            logger.error("CIO: Configuration conflict. Push notifications will not work properly.")
            return true
        }
        
        application.registerForRemoteNotifications()
        
        if shouldSetNotificationCenterDelegate {
            wrappedNoticeCenterDelegate = UNUserNotificationCenter.current().delegate
            UNUserNotificationCenter.current().delegate = self
        }
        
        return result ?? true
    }
    
    open func application(_ application: UIApplication,
                          didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        wrappedAppDelegate?.application?(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }
    
    open func application(_ application: UIApplication,
                          didFailToRegisterForRemoteNotificationsWithError error: Error) {
        wrappedAppDelegate?.application?(application, didFailToRegisterForRemoteNotificationsWithError: error)
        
        logger.error("CIO: Device token is deleted for current user. Failed to register for remote notifications: \(error.localizedDescription)")
        messagingPush.deleteDeviceToken()
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    // Function called when a push notification is clicked or swiped away.
    open func userNotificationCenter(_ center: UNUserNotificationCenter,
                                     didReceive response: UNNotificationResponse,
                                     withCompletionHandler completionHandler: @escaping () -> Void) {
        let _ = messagingPush.userNotificationCenter(center, didReceive: response)
        
        if let wrappedNoticeCenterDelegate = wrappedNoticeCenterDelegate,
           wrappedNoticeCenterDelegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)))
        {
            wrappedNoticeCenterDelegate.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
        } else {
            completionHandler()
        }
    }
    
    // MARK: - method forwarding
    override public func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) {
            return true
        }
        return wrappedAppDelegate?.responds(to: aSelector) ?? false
    }
    
    override public func forwardingTarget(for aSelector: Selector!) -> Any? {
        if super.responds(to: aSelector) {
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
            let errorMessage = "CIO: Missing configuration"
            assertionFailure(errorMessage)
            logger.error(errorMessage)
            return true
        }
        
        guard config.autoFetchDeviceToken == false else {
            let errorMessage = "CIO: 'autoFetchDeviceToken' flag can't be enabled if AppDelegate is used" 
            assertionFailure(errorMessage)
            logger.error(errorMessage)
            return true
        }
        
        guard config.autoTrackPushEvents == false || shouldSetNotificationCenterDelegate == false else {
            let errorMessage = "CIO: 'autoTrackPushEvents' flag can't be enabled if AppDelegate is used with 'shouldSetNotificationCenterDelegate' flag set to true."
            assertionFailure(errorMessage)
            logger.error(errorMessage)
            return true
        }
        
        return false
    }
}
