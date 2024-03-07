import CioMessagingInApp
import CioMessagingPushFCM
import CioDataPipelines
import FirebaseCore
import FirebaseMessaging
import Foundation
import SampleAppsCommon
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Follow setup guide for setting up FCM push: https://firebase.google.com/docs/cloud-messaging/ios/client
        // The FCM SDK provides a device token to the app that you then send to the Customer.io SDK.

        // First, initialize your SDKs.
        // Initialize the Firebase SDK.
        FirebaseApp.configure()

        let appSetSettings = CioSettingsManager().appSetSettings
        let siteId = appSetSettings?.siteId ?? BuildEnvironment.CustomerIO.siteId
        let apiKey = appSetSettings?.apiKey ?? BuildEnvironment.CustomerIO.apiKey

        // Initialize the Customer.io SDK
        CustomerIO.initialize(siteId: siteId, apiKey: apiKey, region: .US) { config in
            // Modify properties in the config object to configure the Customer.io SDK.
            // config.logLevel = .debug // Uncomment this line to enable debug logging.

            // This line of code is internal to Customer.io for testing purposes. Do not add this code to your app.
            appSetSettings?.configureCioSdk(config: &config)
        }
        // Initialize messaging features after initializing Customer.io SDK
        MessagingInApp
            .initialize(siteId: siteId, region: .US)
            .setEventListener(self)
        MessagingPushFCM.initialize { config in
            // Because this is a SwiftUI app, auto fetch device token feature will not work.
            // Therefore, we will forward the device token to the Customer.io SDK.
            config.autoFetchDeviceToken = false
        }

        // Manually get FCM device token. Then, we will forward to the Customer.io SDK.
        Messaging.messaging().delegate = self

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
        MessagingPush.shared.registerDeviceToken(fcmToken: fcmToken)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Function called when a push notification is clicked or swiped away.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Track a Customer.io event for testing purposes to more easily track when this function is called.
        CustomerIO.shared.track(
            name: "push clicked",
            data: ["push": response.notification.request.content.userInfo]
        )

        completionHandler()
    }

    // For testing purposes, it's suggested to not include the willPresent function in the AppDelegate.
    // The automatic push click handling feature uses swizzling. A good edge case to test with swizzling is when
    // there is an optional function of UNUserNotificationCenterDelegate not implemented. By not including willPresent, we are able to test this case.
//    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
}

extension AppDelegate: InAppEventListener {
    func messageShown(message: InAppMessage) {
        CustomerIO.shared.track(
            name: "inapp shown",
            data: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    func messageDismissed(message: InAppMessage) {
        CustomerIO.shared.track(
            name: "inapp dismissed",
            data: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    func errorWithMessage(message: InAppMessage) {
        CustomerIO.shared.track(
            name: "inapp error",
            data: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    func messageActionTaken(message: InAppMessage, actionValue: String, actionName: String) {
        CustomerIO.shared.track(name: "inapp action", data: [
            "delivery-id": message.deliveryId ?? "(none)",
            "message-id": message.messageId,
            "action-value": actionValue,
            "action-name": actionName
        ])
    }
}
