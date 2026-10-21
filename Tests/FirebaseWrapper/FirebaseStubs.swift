import Foundation

// Objective-C stand-ins for FIRMessaging and FIRInstallations, with Firebase's selectors and types, so the runtime
// lookup is tested without linking Firebase. `current == nil` stands for "FirebaseApp.configure() hasn't run".

class MessagingStubBase: NSObject {
    var notificationCenter = NotificationCenter()

    @objc(APNSToken) var apnsToken: Data? {
        didSet { apnsTokenSetCount += 1 }
    }

    var apnsTokenSetCount = 0
    @objc weak var delegate: AnyObject?

    var token: String?
    var tokenError: Error?
    var tokenCallCount = 0
    var apnsTokenWhenTokenRequested: Data?

    @objc(tokenWithCompletion:)
    func token(completion: @escaping (String?, Error?) -> Void) {
        tokenCallCount += 1
        apnsTokenWhenTokenRequested = apnsToken
        completion(token, tokenError)
    }

    /// What FirebaseMessaging does on a new registration: call its delegate, then post the deprecated notification.
    func simulateRegistrationRefresh(_ registration: String?, isInstallationId: Bool) {
        let selector = NSSelectorFromString(isInstallationId ? "messaging:didReceiveRegistration:" : "messaging:didReceiveRegistrationToken:")
        if let delegate = delegate as? NSObject, delegate.responds(to: selector) {
            _ = delegate.perform(selector, with: self, with: registration as NSString?)
        }
        notificationCenter.post(name: Notification.Name("com.firebase.messaging.notif.fcm-token-refreshed"), object: registration)
    }
}

/// FirebaseMessaging before 12.16: no FID registration.
@objc(CioTestTokenOnlyMessaging)
final class TokenOnlyMessagingStub: MessagingStubBase {
    static var current: TokenOnlyMessagingStub?
    static var messagingCallCount = 0

    @objc class func messaging() -> TokenOnlyMessagingStub? {
        messagingCallCount += 1
        return current
    }
}

/// FirebaseMessaging 12.16+: adds FID registration.
@objc(CioTestFIDMessaging)
final class FIDMessagingStub: MessagingStubBase {
    static var current: FIDMessagingStub?

    var installationIdEnabled = false
    var registerError: Error?
    var registerCallCount = 0

    @objc class func messaging() -> FIDMessagingStub? {
        current
    }

    @objc var isInstallationIdEnabled: Bool {
        installationIdEnabled
    }

    @objc(registerWithCompletion:)
    func register(completion: @escaping (Error?) -> Void) {
        registerCallCount += 1
        completion(registerError)
    }
}

/// A FirebaseMessaging whose token method takes a different type under the same selector.
@objc(CioTestIncompatibleMessaging)
final class IncompatibleMessagingStub: NSObject {
    static var current: IncompatibleMessagingStub?
    var tokenCallCount = 0

    @objc class func messaging() -> IncompatibleMessagingStub? {
        current
    }

    @objc(APNSToken) var apnsToken: Data?
    @objc weak var delegate: AnyObject?

    @objc(tokenWithCompletion:)
    func token(completion: NSString) {
        tokenCallCount += 1
    }
}

@objc(CioTestInstallations)
final class InstallationsStub: NSObject {
    static var current: InstallationsStub?
    var installationId: String?

    @objc class func installations() -> InstallationsStub? {
        current
    }

    @objc(installationIDWithCompletion:)
    func installationID(completion: @escaping (String?, Error?) -> Void) {
        completion(installationId, nil)
    }
}

/// An app's own MessagingDelegate.
final class AppMessagingDelegateSpy: NSObject {
    var tokens: [String?] = []
    var registrations: [String?] = []
    var unregistrations: [String] = []

    @objc(messaging:didReceiveRegistrationToken:)
    func messaging(_ messaging: NSObject, didReceiveRegistrationToken token: String?) {
        tokens.append(token)
    }

    @objc(messaging:didReceiveRegistration:)
    func messaging(_ messaging: NSObject, didReceiveRegistration installationId: String?) {
        registrations.append(installationId)
    }

    @objc(messaging:didUnregister:)
    func messaging(_ messaging: NSObject, didUnregister installationId: String) {
        unregistrations.append(installationId)
    }
}

/// A delegate that chains to the one it replaced, like RNFirebase's.
final class ChainingMessagingDelegate: NSObject {
    weak var previous: NSObject?
    var tokens: [String?] = []

    @objc(messaging:didReceiveRegistrationToken:)
    func messaging(_ messaging: NSObject, didReceiveRegistrationToken token: String?) {
        tokens.append(token)
        let selector = NSSelectorFromString("messaging:didReceiveRegistrationToken:")
        if let previous = previous, previous.responds(to: selector) {
            _ = previous.perform(selector, with: messaging, with: token as NSString?)
        }
    }
}

/// FirebaseCore's `FIRApp`, for its quiet `+isDefaultAppConfigured`.
@objc(CioTestFirebaseApp)
final class FirebaseAppStub: NSObject {
    static var isConfigured = false

    @objc class func isDefaultAppConfigured() -> Bool {
        isConfigured
    }
}
