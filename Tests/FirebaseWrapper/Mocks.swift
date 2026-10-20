// Moved from customerio/customerio-ios-fcm (Tests/Mocks.swift). Compiled only with the FCM trait.
#if FCM
@testable import CioFirebaseWrapper
import CioMessagingPushFCM
import FirebaseMessaging
import Foundation

// MARK: - Mock FirebaseMessaging

class MockFirebaseMessaging {
    var mockApnsToken: Data?
    var mockDelegate: MessagingDelegate?
    var tokenCompletion: ((String?, Error?) -> Void)?
    var tokenCallCount = 0

    // Helper methods for testing
    func simulateTokenSuccess(_ token: String) {
        tokenCompletion?(token, nil)
    }

    func simulateTokenError(_ error: Error) {
        tokenCompletion?(nil, error)
    }

    func simulateRegistrationToken(_ token: String?) {
        if let delegate = mockDelegate {
            let messaging = Messaging.messaging()
            delegate.messaging!(messaging, didReceiveRegistrationToken: token)
        }
    }
}

// MARK: - Test Error

enum TestError: Error, Equatable {
    case networkError
    case tokenError
    case configurationError
}

// MARK: - Test Data

enum TestData {
    static let validApnsToken = Data([0x01, 0x02, 0x03, 0x04, 0x05])
    static let validFCMToken = "valid_fcm_token_12345"
    static let invalidToken = ""
}

// MARK: - Firebase Messaging Mocks (moved from customerio-ios)

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

// MARK: - Mock FirebaseServiceDelegate

class MockFirebaseServiceDelegate: FirebaseServiceDelegate {
    var receivedToken: String?
    var tokenCallCount = 0
    var receivedRegistrations: [String?] = []

    func didReceiveRegistrationToken(_ token: String?) {
        receivedToken = token
        tokenCallCount += 1
    }

    func didReceiveRegistration(_ installationId: String?) {
        receivedRegistrations.append(installationId)
    }
}
#endif
