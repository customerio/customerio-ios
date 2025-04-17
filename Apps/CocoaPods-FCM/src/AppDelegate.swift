import CioDataPipelines
import CioMessagingInApp
import CioMessagingPushFCM
import FirebaseCore
import FirebaseMessaging
import Foundation
import SampleAppsCommon
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    let anotherPushEventHandler = AnotherPushEventHandler()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Follow setup guide for setting up FCM push: https://firebase.google.com/docs/cloud-messaging/ios/client
        // The FCM SDK provides a device token to the app that you then send to the Customer.io SDK.

        // First, initialize your SDKs.
        // Initialize the Firebase SDK.
        FirebaseApp.configure()

        let appSetSettings = CioSettingsManager().appSetSettings
        let siteId = appSetSettings?.siteId ?? BuildEnvironment.CustomerIO.siteId
        let cdpApiKey = appSetSettings?.cdpApiKey ?? BuildEnvironment.CustomerIO.cdpApiKey

        // Configure and initialize the Customer.io SDK
        let config = SDKConfigBuilder(cdpApiKey: cdpApiKey)
            .region(.US)
            .migrationSiteId(siteId)
            .flushAt(appSetSettings?.flushAt ?? 10)
            .flushInterval(Double(appSetSettings?.flushInterval ?? 30))
            .autoTrackDeviceAttributes(appSetSettings?.trackDeviceAttributes ?? true)
        let logLevel = appSetSettings?.debugSdkMode
        if logLevel == nil || logLevel == true {
            config.logLevel(CioLogLevel.debug)
        }
        if let apiHost = appSetSettings?.apiHost, !apiHost.isEmpty {
            config.apiHost(apiHost)
        }
        if let cdnHost = appSetSettings?.cdnHost, !cdnHost.isEmpty {
            config.cdnHost(cdnHost)
        }
        CustomerIO.initialize(withConfig: config.build())

        // Initialize messaging features after initializing Customer.io SDK
        MessagingInApp
            .initialize(withConfig: MessagingInAppConfigBuilder(siteId: siteId, region: .US).build())
            .setEventListener(self)
        MessagingPushFCM.initialize(
            withConfig: MessagingPushConfigBuilder()
                .autoFetchDeviceToken(false)
                .autoTrackPushEvents(false)
                .build()
        )

        // Manually get FCM device token. Then, we will forward to the Customer.io SDK.
        Messaging.messaging().delegate = self

        /*
         Next line of code is testing how Firebase behaves when another object is set as the delegate for `UNUserNotificationCenter`.
         This is not necessary for the Customer.io SDK to work.
         */
        UNUserNotificationCenter.current().delegate = anotherPushEventHandler

        /**
         Registers the `AppDelegate` class to handle when a push notification gets clicked.
         This line of code is optional and only required if you have custom code that needs to run when a push notification gets clicked on.
         Push notifications sent by Customer.io will be handled by the Customer.io SDK automatically, unless you disabled that feature. Therefore, this line of code is not required if you only want to handle push notifications sent by Customer.io.

         We register a click handler in this app for testing purposes, only. To test that the Customer.io SDK is compatible with other SDKs that want to process push notifications not sent by Customer.io.
         */
        UNUserNotificationCenter.current().delegate = self

        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
}

extension AppDelegate: MessagingDelegate {
    // Function that is called when a new FCM device token is assigned to device.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // Forward the device token to the Customer.io SDK:
        // This in needed only if `shouldSetMessagingDelegate` is overriden to `false`
//        MessagingPush.shared.registerDeviceToken(fcmToken: fcmToken)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Function called when a push notification is clicked or swiped away.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Track a Customer.io event for testing purposes to more easily track when this function is called.
        // This is not necessary, as our AppDelegate is already caching this
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

    // For QA testing, it's suggested to not implement this optional function.
    // The SDK contains logic that handles when this optional function is implemented in a host iOS app, or not. Do not implement it to test the use case.
    //
//    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
}

extension AppDelegate: InAppEventListener {
    func messageShown(message: InAppMessage) {
        CustomerIO.shared.track(
            name: "inapp shown",
            properties: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    func messageDismissed(message: InAppMessage) {
        CustomerIO.shared.track(
            name: "inapp dismissed",
            properties: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    func errorWithMessage(message: InAppMessage) {
        CustomerIO.shared.track(
            name: "inapp error",
            properties: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    func messageActionTaken(message: InAppMessage, actionValue: String, actionName: String) {
        CustomerIO.shared.track(name: "inapp action", properties: [
            "delivery-id": message.deliveryId ?? "(none)",
            "message-id": message.messageId,
            "action-value": actionValue,
            "action-name": actionName
        ])
    }
}
