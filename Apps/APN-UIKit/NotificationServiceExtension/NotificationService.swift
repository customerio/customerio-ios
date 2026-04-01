import CioInternalCommon
import CioMessagingPush
import CioMessagingPushAPN
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        MessagingPushAPN.initializeForExtension(
            withConfig: MessagingPushConfigBuilder(cdpApiKey: BuildEnvironment.CustomerIO.cdpApiKey)
                .logLevel(.debug)
                .appGroupId("group.io.customer.ios-sample.apn-spm.APN-UIKit.cio")
                .build()
        )

        MessagingPush.shared.didReceive(request, withContentHandler: contentHandler)
    }

    override func serviceExtensionTimeWillExpire() {
        MessagingPush.shared.serviceExtensionTimeWillExpire()
    }
}
