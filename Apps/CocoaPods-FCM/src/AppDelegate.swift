import CioMessagingInApp
import CioMessagingPushFCM
import CioTracking
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
            config.autoTrackPushEvents = true
            // config.logLevel = .debug // Uncomment this line to enable debug logging.

            // This line of code is internal to Customer.io for testing purposes. Do not add this code to your app.
            appSetSettings?.configureCioSdk(config: &config)
        }
        // Initialize messaging features after initializing Customer.io SDK
        MessagingInApp.initialize(eventListener: self)
        MessagingPushFCM.initialize { config in
            config.autoFetchDeviceToken = true
        }

        return true
    }
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
