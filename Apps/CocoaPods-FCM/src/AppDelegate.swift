import CioMessagingPushFCM
import CioTracking
import FirebaseCore
import FirebaseMessaging
import Foundation
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()

        // we are only using this sample app for testing it can compile so providing a siteid and apikey is not useful at the moment.
        CustomerIO.initialize(siteId: "", apiKey: "", region: .US) { config in
            config.logLevel = .debug
        }

        UIApplication.shared.registerForRemoteNotifications()

        Messaging.messaging().delegate = self

        return true
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        CustomerIO.shared.identify(identifier: "foo@customer.io", body: ["first_name": "Dana"])

        MessagingPush.shared.registerDeviceToken(fcmToken: fcmToken)
    }
}
