import MessagingPush
import Common

/**
 Swift code goes into this module that is specific to APN push notification messaging.
  */
public class MessagingPushAPN: MessagingPush {
    public func register(deviceToken: String, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        self.registerDeviceToken(deviceToken: deviceToken, onComplete: onComplete)
    }
    
    public func unregister(onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        self.deleteDeviceToken(onComplete: onComplete)
    }
}
