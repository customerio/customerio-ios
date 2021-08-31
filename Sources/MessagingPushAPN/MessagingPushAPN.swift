import Foundation
import UIKit
import CioTracking
import CioMessagingPush

/**
 Swift code goes into this module that is specific to APN push notification messaging.
  */
public extension MessagingPush {
    
    func registerForRemoteNotifications(){
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        self.registerDeviceToken(deviceToken: deviceToken, onComplete:onComplete)
      }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Print to XCode logs the error
    }
}

