import CioMessagingPushFCM
import CioTracking
import SampleAppsCommon
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        // This code is internal to Customer.io for testing purposes. Your app will be unique
        // in how you decide to provide the siteId, apiKey, and region to the SDK.
        let appSetSettings = CioSettingsManager().appSetSettings
        let siteId = appSetSettings?.siteId ?? BuildEnvironment.CustomerIO.siteId
        let apiKey = appSetSettings?.apiKey ?? BuildEnvironment.CustomerIO.apiKey

        // You must initialize the Customer.io SDK inside of the Notification Service.
        CustomerIO.initialize(siteId: siteId, apiKey: apiKey, region: .US) { config in
            // Modify properties in the config object to configure the Customer.io SDK.
            // config.logLevel = .debug // Uncomment this line to enable debug logging.

            // This line of code is internal to Customer.io for testing purposes. Do not add this code to your app.
            appSetSettings?.configureCioSdk(config: &config)
        }

        // Then, send the request to the Customer.io SDK for processing.
        MessagingPush.shared.didReceive(request, withContentHandler: contentHandler)
    }

    override func serviceExtensionTimeWillExpire() {
        MessagingPush.shared.serviceExtensionTimeWillExpire()
    }
}
