import Foundation
import CioTracking
import CioMessagingPush

/**
 MessagingPush extension to support APN push notification messaging.
  */
public extension MessagingPush {
    
    func application(_ application: Any, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        self.registerDeviceToken(deviceToken, onComplete:onComplete)
      }

    func application(_ application: Any, didFailToRegisterForRemoteNotificationsWithError error: Error, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        self.deleteDeviceToken(onComplete: onComplete)
    }
}

