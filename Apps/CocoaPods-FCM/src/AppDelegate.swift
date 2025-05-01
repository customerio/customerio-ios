import CioDataPipelines
import CioMessagingInApp
import CioMessagingPushFCM
import FirebaseCore
import FirebaseMessaging
import Foundation
import SampleAppsCommon
import UIKit

class AppDelegateWithCioIntegration: CioAppDelegateFCMWrapper<AppDelegate> {
    // Two properties below are not necessary. Add them only if you want to chenge default 'true` value.
    override var shouldIntegrateWithNotificationCenter: Bool {
        true
    }

    override var shouldIntegrateWithFirebaseMessaging: Bool {
        true
    }
}

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

        // This is old deprecated way - do not use this any more and instead follow deprecation instruction
//        let config = SDKConfigBuilder(cdpApiKey: cdpApiKey)
        // Configure and initialize the Customer.io SDK
        let config = CioSdkConfigBuilder(cdpApiKey: cdpApiKey)
            .region(.US)
            .migrationSiteId(siteId)
            .flushAt(appSetSettings?.flushAt ?? 10)
            .flushInterval(Double(appSetSettings?.flushInterval ?? 30))
            .autoTrackDeviceAttributes(appSetSettings?.trackDeviceAttributes ?? true)
            .deepLinkCallback { (url: URL) in
                // You can call any method to process this furhter,
                // or redirect it to `application(_:continue:restorationHandler:)` for consistency, if you use deep-linking in Firebase
                let openLinkInHostAppActivity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
                openLinkInHostAppActivity.webpageURL = url
                return self.application(UIApplication.shared, continue: openLinkInHostAppActivity, restorationHandler: { _ in })
            }
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
        // Call below is not needed if CioAppDelegateFCM/CioAppDelegateFCMWrapper is used
//        MessagingPushFCM.initialize(
//            withConfig: MessagingPushConfigBuilder()
//                .autoFetchDeviceToken(false)
//                .autoTrackPushEvents(false)
//                .build()
//        )

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
        // This is NOT necessary if CioAppDelegateFCM is used with `shouldIntegrateWithFirebaseMessaging` set as `true`.
//        Messaging.messaging().apnsToken = deviceToken
    }

    // IMPORTANT: If FCM is used with enabled swizzling (default state) it will not call this method in SwiftUI based apps.
    //            Use `deepLinkCallback` on CioSdkConfigBuilder, as this works in all scenarios.
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([any UIUserActivityRestoring]?) -> Void) -> Bool {
        guard let universalLinkUrl = userActivity.webpageURL else {
            return false
        }
        print("universalLinkUrl: \(universalLinkUrl)")
        return true
    }
}

extension AppDelegate: MessagingDelegate {
    // Function that is called when a new FCM device token is assigned to device.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // This is NOT necessary if CioAppDelegateFCM is used with `shouldIntegrateWithFirebaseMessaging` set as `true`.
//        MessagingPush.shared.registerDeviceToken(fcmToken: fcmToken)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Function called when a push notification is clicked or swiped away.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Track custom event with Customer.io.
        // NOT required for basic PN tap tracking - that is done automatically with `CioAppDelegateFCMWrapper`.
        CustomerIO.shared.track(
            name: "custom push-clicked event",
            properties: ["push": response.notification.request.content.userInfo]
        )

        completionHandler()
    }

    // To test sending of local notifications, display the push while app in foreground. So when you press the button to display local push in the app, you are able to see it and click on it.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .badge, .sound])
    }
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
