import CioMessagingPush
import Foundation
import UIKit

extension MessagingPushAPN: AppDelegateSwizzlerDelegate {
    public func didReceiveAPNSToken(_ deviceToken: Data) {
        MessagingPush.shared.registerDeviceToken(apnDeviceToken: deviceToken)
    }

    @available(iOSApplicationExtension, unavailable)
    func setupAutoFetchDeviceToken() {
        // Swizzle method `didRegisterForRemoteNotificationsWithDeviceToken`
        AppDelegateSwizzler.startSwizzlingIfPossible(self)
        // Register for push notifications to invoke`didRegisterForRemoteNotificationsWithDeviceToken` method
        UIApplication.shared.registerForRemoteNotifications()
    }
}
