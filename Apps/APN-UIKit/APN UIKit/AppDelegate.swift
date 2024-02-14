import CioDataPipelines
import CioInternalCommon
import CioMessagingInApp
import CioMessagingPushAPN
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var storage = DIGraph.shared.storage
    var deepLinkHandler = DIGraph.shared.deepLinksHandlerUtil

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.

        // Register for remote notifications using APN. On successful registration,
        // didRegisterForRemoteNotifications delegate method will be called and it
        // provides a device token. In case, registration fails then
        // didFailToRegisterForRemoteNotifications will be called.
        initializeCioAndInAppListeners()
        UNUserNotificationCenter.current().delegate = self

        return true
    }

    func initializeCioAndInAppListeners() {
        // Initialize CustomerIO SDK

        if storage.didSetDefaults == false {
            storage.didSetDefaults = true
            storage.isDebugModeEnabled = true
            storage.isTrackScreenEnabled = true
            storage.isTrackDeviceAttrEnabled = true
        }
        var writeKey = BuildEnvironment.CustomerIO.writeKey
        var siteId = BuildEnvironment.CustomerIO.siteId
        if let storedSiteId = storage.siteId {
            siteId = storedSiteId
        }
        if let storedWriteKey = storage.writeKey {
            writeKey = storedWriteKey
        }
        let logLevel = storage.isDebugModeEnabled ?? true ? CioLogLevel.debug : CioLogLevel.error
        CustomerIO.initialize(writeKey: writeKey, logLevel: logLevel) { config in
            config.autoTrackDeviceAttributes = self.storage.isTrackDeviceAttrEnabled ?? true
            config.flushInterval = Double(self.storage.bgQDelay ?? "30") ?? 30
            config.flushAt = Int(self.storage.bgNumOfTasks ?? "10") ?? 10
            if let apiHost = self.storage.apiHost, !apiHost.isEmpty {
                config.apiHost = apiHost
            }
            if let cdnHost = self.storage.cdnHost, !cdnHost.isEmpty {
                config.cdnHost = cdnHost
            }
        }

        let autoScreenTrack = storage.isTrackScreenEnabled ?? true
        if autoScreenTrack {
            CustomerIO.shared.add(plugin: AutoTrackingScreenViews(filterAutoScreenViewEvents: nil, autoScreenViewBody: nil))
        }

        // Add event listeners for in-app. This is not to initialise in-app but event listeners for in-app.
        MessagingInApp
            .initialize(siteId: siteId, region: .US)
            .setEventListener(self)
        MessagingPushAPN.initialize { config in
            config.autoFetchDeviceToken = true
        }
    }

    // Handle Universal Link deep link from the Customer.io SDK. This function will get called if a push notification
    // gets clicked that has a Universal Link deep link attached and the app is in the foreground. Otherwise, another function
    // in your app may get called depending on what technology you use (Scenes, UIKit, Swift UI).
    //
    // Learn more: https://customer.io/docs/sdk/ios/push/#universal-links-deep-links
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard let universalLinkUrl = userActivity.webpageURL else {
            return false
        }

        return deepLinkHandler.handleUniversalLinkDeepLink(universalLinkUrl)
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Delegate called when user responds to a notification. Set delegate in
    // application:didFinishLaunchingWithOptions: method.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let handled = MessagingPush.shared.userNotificationCenter(
            center,
            didReceive: response,
            withCompletionHandler: completionHandler
        )

        // If the Customer.io SDK does not handle the push, it's up to you to handle it and call the
        // completion handler. If the SDK did handle it, it called the completion handler for you.
        if !handled {
            completionHandler()
        }
    }

    // OPTIONAL: Delegate method only runs when app is active(foreground). If not implemented or delayed, notification won't show in foreground. App can show notification as sound, badge, or alert..
    @available(iOS 10.0, *)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions)
            -> Void
    ) {
        completionHandler([.list, .banner, .badge, .sound])
    }
}

// In-app event listeners to handle user's response to in-app messages.
// Registering event listeners is requiredf
extension AppDelegate: InAppEventListener {
    // Message is sent and shown to the user
    func messageShown(message: InAppMessage) {
        CustomerIO.shared.track(
            name: "inapp shown",
            properties: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    // User taps X (close) button and in-app message is dismissed
    func messageDismissed(message: InAppMessage) {
        CustomerIO.shared.track(
            name: "inapp dismissed",
            properties: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    // In-app message produces an error - preventing message from appearing to the user
    func errorWithMessage(message: InAppMessage) {
        CustomerIO.shared.track(
            name: "inapp error",
            properties: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    // User perform an action on in-app message
    func messageActionTaken(message: InAppMessage, actionValue: String, actionName: String) {
        if actionName == "remove" || actionName == "test" {
            MessagingInApp.shared.dismissMessage()
        }
        CustomerIO.shared.track(name: "inapp action", properties: [
            "delivery-id": message.deliveryId ?? "(none)",
            "message-id": message.messageId,
            "action-value": actionValue,
            "action-name": actionName
        ])
    }
}
