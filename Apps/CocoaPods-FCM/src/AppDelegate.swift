import CioMessagingPushFCM
import CioTracking
import FirebaseCore
import FirebaseMessaging
import Foundation
import SampleAppsCommon
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()

        let appSetSettings = CioSettingsManager().appSetSettings
        let siteId = appSetSettings?.siteId ?? ""
        let apiKey = appSetSettings?.apiKey ?? ""

        // we are only using this sample app for testing it can compile so providing a siteid and apikey is not useful at the moment.
        CustomerIO.initialize(siteId: siteId, apiKey: apiKey, region: .US) { config in
            // Modify properties in the config object to configure the Customer.io SDK.

            config.logLevel = .debug // For all of our sample apps, we prefer to set debug logs to make our internal testing easier. You may not need to do this.

            // This line of code is internal to Customer.io for testing purposes. Do not add this code to your app.
            appSetSettings?.configureCioSdk(config: &config)
        }

        UIApplication.shared.registerForRemoteNotifications()

        Messaging.messaging().delegate = self

        return true
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        MessagingPush.shared.registerDeviceToken(fcmToken: fcmToken)
    }
}
