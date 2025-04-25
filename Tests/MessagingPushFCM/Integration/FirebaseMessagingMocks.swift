import FirebaseMessaging

class MockMessagingDelegate: NSObject, MessagingDelegate {
    var didReceiveRegistrationTokenCalled = false
    var fcmTokenReceived: String?

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        didReceiveRegistrationTokenCalled = true
        fcmTokenReceived = fcmToken
    }
}

public extension Messaging {
    static func swizzleMessaging() {
        let originalMethod = class_getClassMethod(Messaging.self, #selector(Messaging.messaging))!
        let swizzledMethod = class_getClassMethod(Messaging.self, #selector(Messaging.messagingMock))!
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    static func unswizzleMessaging() {
        swizzleMessaging() // Calling again will swap back
    }

    @objc class func messagingMock() -> Messaging {
        let dummyObject = NSObject()
        let messaging = unsafeBitCast(dummyObject, to: Messaging.self)
        return messaging
    }
}
