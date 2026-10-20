@testable import CioFirebaseWrapper
import CioMessagingPushFCM
import XCTest

// Objective-C stand-ins for FIRMessaging and FIRInstallations, with the same selectors, so the runtime lookup is tested
// without linking Firebase.
@objc(CioTestTokenOnlyMessaging)
private final class TokenOnlyMessagingStub: NSObject {
    static var current = TokenOnlyMessagingStub()

    @objc(APNSToken) var apnsToken: Data?
    var token: String?
    var tokenError: Error?

    @objc class func messaging() -> TokenOnlyMessagingStub {
        current
    }

    @objc(tokenWithCompletion:)
    func token(completion: @escaping (String?, Error?) -> Void) {
        completion(token, tokenError)
    }
}

// FirebaseMessaging 12.16.0+: adds FID registration.
@objc(CioTestFIDMessaging)
private final class FIDMessagingStub: NSObject {
    static var current = FIDMessagingStub()

    @objc(APNSToken) var apnsToken: Data?
    var installationIdEnabled = false
    var registerError: Error?
    var registerCallCount = 0

    @objc class func messaging() -> FIDMessagingStub {
        current
    }

    @objc(tokenWithCompletion:)
    func token(completion: @escaping (String?, Error?) -> Void) {
        completion("token", nil)
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

// `+[FIRMessaging messaging]` before `FirebaseApp.configure()`: the class exists, the instance doesn't.
@objc(CioTestUnconfiguredMessaging)
private final class UnconfiguredMessagingStub: NSObject {
    @objc class func messaging() -> UnconfiguredMessagingStub? {
        nil
    }
}

@objc(CioTestInstallations)
private final class InstallationsStub: NSObject {
    static var current = InstallationsStub()

    var installationId: String?

    @objc class func installations() -> InstallationsStub {
        current
    }

    @objc(installationIDWithCompletion:)
    func installationID(completion: @escaping (String?, Error?) -> Void) {
        completion(installationId, nil)
    }
}

private class FirebaseServiceDelegateSpy: FirebaseServiceDelegate {
    var tokens: [String?] = []
    var registrations: [String?] = []

    func didReceiveRegistrationToken(_ token: String?) {
        tokens.append(token)
    }

    func didReceiveRegistration(_ installationId: String?) {
        registrations.append(installationId)
    }
}

class FirebaseImplTests: XCTestCase {
    private var notificationCenter: NotificationCenter!

    override func setUp() {
        super.setUp()
        notificationCenter = NotificationCenter()
        TokenOnlyMessagingStub.current = TokenOnlyMessagingStub()
        FIDMessagingStub.current = FIDMessagingStub()
        InstallationsStub.current = InstallationsStub()
    }

    private func tokenOnlyImpl() -> FirebaseImpl {
        FirebaseImpl(notificationCenter: notificationCenter, messagingClassName: "CioTestTokenOnlyMessaging", installationsClassName: "CioTestInstallations")
    }

    private func fidImpl() -> FirebaseImpl {
        FirebaseImpl(notificationCenter: notificationCenter, messagingClassName: "CioTestFIDMessaging", installationsClassName: "CioTestInstallations")
    }

    func test_apnsToken_givenMessagingLinked_expectSetOnMessaging() {
        let impl = tokenOnlyImpl()
        let token = Data([0x01, 0x02])

        impl.apnsToken = token

        XCTAssertEqual(TokenOnlyMessagingStub.current.apnsToken, token)
        XCTAssertEqual(impl.apnsToken, token)
    }

    func test_fetchToken_givenMessagingLinked_expectTokenFromMessaging() {
        TokenOnlyMessagingStub.current.token = "fcm-token"
        var received: String?

        tokenOnlyImpl().fetchToken { token, _ in received = token }

        XCTAssertEqual(received, "fcm-token")
    }

    func test_fetchToken_givenMessagingNotLinked_expectNotLinkedError() {
        let impl = FirebaseImpl(notificationCenter: notificationCenter, messagingClassName: "CioTestMissingClass")
        var receivedError: Error?

        impl.fetchToken { _, error in receivedError = error }

        XCTAssertFalse(impl.isFirebaseMessagingLinked)
        XCTAssertEqual(receivedError as? FirebaseImplError, .firebaseMessagingNotLinked)
        XCTAssertNil(impl.apnsToken)
    }

    func test_fetchToken_givenFirebaseNotConfigured_expectNotConfiguredError() {
        let impl = FirebaseImpl(notificationCenter: notificationCenter, messagingClassName: "CioTestUnconfiguredMessaging")
        var receivedError: Error?

        impl.fetchToken { _, error in receivedError = error }

        XCTAssertTrue(impl.isFirebaseMessagingLinked)
        XCTAssertEqual(receivedError as? FirebaseImplError, .firebaseNotConfigured)
    }

    func test_isInstallationIdEnabled_givenFirebaseWithoutFID_expectFalse() {
        XCTAssertTrue(tokenOnlyImpl().isFirebaseMessagingLinked)
        XCTAssertFalse(tokenOnlyImpl().isInstallationIdEnabled)
    }

    func test_isInstallationIdEnabled_givenFIDEnabled_expectTrue() {
        FIDMessagingStub.current.installationIdEnabled = true

        XCTAssertTrue(fidImpl().isInstallationIdEnabled)
    }

    func test_fetchInstallationId_givenRegistrationSucceeds_expectInstallationId() {
        InstallationsStub.current.installationId = "fid-123"
        var received: String?

        fidImpl().fetchInstallationId { fid, _ in received = fid }

        XCTAssertEqual(FIDMessagingStub.current.registerCallCount, 1)
        XCTAssertEqual(received, "fid-123")
    }

    func test_fetchInstallationId_givenRegistrationFails_expectError() {
        FIDMessagingStub.current.registerError = NSError(domain: "test", code: 1)
        InstallationsStub.current.installationId = "fid-123"
        var received: String?
        var receivedError: Error?

        fidImpl().fetchInstallationId { fid, error in
            received = fid
            receivedError = error
        }

        XCTAssertNil(received)
        XCTAssertNotNil(receivedError)
    }

    func test_fetchInstallationId_givenFirebaseWithoutFID_expectNilWithoutError() {
        var called = false
        var received: String?
        var receivedError: Error?

        tokenOnlyImpl().fetchInstallationId { fid, error in
            called = true
            received = fid
            receivedError = error
        }

        XCTAssertTrue(called)
        XCTAssertNil(received)
        XCTAssertNil(receivedError)
    }

    func test_registrationNotification_givenTokenMode_expectTokenForwarded() {
        let impl = tokenOnlyImpl()
        let delegate = FirebaseServiceDelegateSpy()
        impl.delegate = delegate

        notificationCenter.post(name: FirebaseImpl.registrationRefreshedNotification, object: "new-token")

        XCTAssertEqual(delegate.tokens, ["new-token"])
        XCTAssertTrue(delegate.registrations.isEmpty)
    }

    func test_registrationNotification_givenFIDMode_expectRegistrationForwarded() {
        FIDMessagingStub.current.installationIdEnabled = true
        let impl = fidImpl()
        let delegate = FirebaseServiceDelegateSpy()
        impl.delegate = delegate

        notificationCenter.post(name: FirebaseImpl.registrationRefreshedNotification, object: "new-fid")

        XCTAssertEqual(delegate.registrations, ["new-fid"])
        XCTAssertTrue(delegate.tokens.isEmpty)
    }
}
