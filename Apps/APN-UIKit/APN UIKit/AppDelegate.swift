import CioDataPipelines
import CioMessagingInApp
import CioMessagingPushAPN
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var storage = DIGraphShared.shared.storage
    var deepLinkHandler = DIGraphShared.shared.deepLinksHandlerUtil

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.

        initializeCioAndInAppListeners()

        /**
         Registers the `AppDelegate` class to handle when a push notification gets clicked.
         This line of code is optional and only required if you have custom code that needs to run when a push notification gets clicked on.
         Push notifications sent by Customer.io will be handled by the Customer.io SDK automatically, unless you disabled that feature. Therefore, this line of code is not required if you only want to handle push notifications sent by Customer.io.

         We register a click handler in this app for testing purposes, only. To test that the Customer.io SDK is compatible with other SDKs that want to process push notifications not sent by Customer.io.
         */
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
        var cdpApiKey = BuildEnvironment.CustomerIO.cdpApiKey
        var siteId = BuildEnvironment.CustomerIO.siteId
        if let storedSiteId = storage.siteId {
            siteId = storedSiteId
        }
        if let storedCdpApiKey = storage.cdpApiKey {
            cdpApiKey = storedCdpApiKey
        }
        let logLevel = storage.isDebugModeEnabled ?? true ? CioLogLevel.debug : CioLogLevel.error
        let config = SDKConfigBuilder(cdpApiKey: cdpApiKey)
            .logLevel(logLevel)
            .flushAt(Int(storage.bgNumOfTasks ?? "10") ?? 10)
            .flushInterval(Double(storage.bgQDelay ?? "30") ?? 30)
            .autoTrackDeviceAttributes(storage.isTrackDeviceAttrEnabled ?? true)
            .migrationSiteId(siteId)

        if let apiHost = storage.apiHost, !apiHost.isEmpty {
            config.apiHost(apiHost)
        }
        if let cdnHost = storage.cdnHost, !cdnHost.isEmpty {
            config.cdnHost(cdnHost)
        }
        if storage.isTrackScreenEnabled == true {
            config.autoTrackUIKitScreenViews()
        }
        CustomerIO.initialize(withConfig: config.build())

        // Initialize messaging features after initializing Customer.io SDK
        MessagingInApp
            .initialize(withConfig: MessagingInAppConfigBuilder(siteId: siteId, region: .US).build())
            .setEventListener(self)
        MessagingPushAPN.initialize(
            withConfig: MessagingPushConfigBuilder()
                .autoFetchDeviceToken(true)
                .build()
        )
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
    // Function called when a push notification is clicked or swiped away.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Track a Customer.io event for testing purposes to more easily track when this function is called.
        CustomerIO.shared.track(
            name: "push clicked",
            properties: ["push": response.notification.request.content.userInfo]
        )

        completionHandler()
    }

    // To test sending of local notifications, display the push while app in foreground. So when you press the button to display local push in the app, you are able to see it and click on it.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .badge, .sound])
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
