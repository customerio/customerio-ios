// Moved from customerio/customerio-ios-fcm (Tests/FirebaseImplTests.swift). Compiled only with the FCM trait.
#if FCM
@testable import CioFirebaseWrapper
import FirebaseMessaging
import XCTest

/// Stands in for `Messaging` on Firebase versions with FID registration (12.16.0+).
private final class FIDMessagingStub: NSObject {
    static var current: NSObject = .init()

    var installationIdEnabled = false
    var registerError: Error?
    var registerCallCount = 0
    var delegateSetCount = 0

    @objc var delegate: AnyObject? {
        didSet { delegateSetCount += 1 }
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

private extension Messaging {
    static func swizzleFIDMessaging() {
        let originalMethod = class_getClassMethod(Messaging.self, #selector(Messaging.messaging))!
        let swizzledMethod = class_getClassMethod(Messaging.self, #selector(Messaging.fidMessagingMock))!
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    @objc class func fidMessagingMock() -> Messaging {
        unsafeBitCast(FIDMessagingStub.current, to: Messaging.self)
    }
}

class FirebaseImplTests: XCTestCase {
    private var firebaseImpl: FirebaseImpl!
    private var notificationCenter: NotificationCenter!

    override func setUp() {
        super.setUp()

        Messaging.swizzleFIDMessaging()
        notificationCenter = NotificationCenter()
        firebaseImpl = FirebaseImpl(notificationCenter: notificationCenter)
    }

    override func tearDown() {
        Messaging.swizzleFIDMessaging() // swaps back
        FIDMessagingStub.current = NSObject()
        firebaseImpl = nil
        notificationCenter = nil

        super.tearDown()
    }

    func testIsInstallationIdEnabled_givenFirebaseWithoutFidRegistration_expectFalse() {
        FIDMessagingStub.current = NSObject()

        XCTAssertFalse(firebaseImpl.isInstallationIdEnabled)
    }

    func testIsInstallationIdEnabled_givenFidModeOn_expectTrue() {
        let messaging = FIDMessagingStub()
        messaging.installationIdEnabled = true
        FIDMessagingStub.current = messaging

        XCTAssertTrue(firebaseImpl.isInstallationIdEnabled)
    }

    func testIsInstallationIdEnabled_givenFidModeOff_expectFalse() {
        FIDMessagingStub.current = FIDMessagingStub()

        XCTAssertFalse(firebaseImpl.isInstallationIdEnabled)
    }

    func testFetchInstallationId_givenFirebaseWithoutFidRegistration_expectNoFid() {
        FIDMessagingStub.current = NSObject()
        var result: (fid: String?, error: Error?)?

        firebaseImpl.fetchInstallationId { result = ($0, $1) }

        XCTAssertNotNil(result)
        XCTAssertNil(result?.fid)
        XCTAssertNil(result?.error)
    }

    func testFetchInstallationId_givenRegisterFails_expectError() {
        let messaging = FIDMessagingStub()
        messaging.installationIdEnabled = true
        messaging.registerError = TestError.networkError
        FIDMessagingStub.current = messaging
        var result: (fid: String?, error: Error?)?

        firebaseImpl.fetchInstallationId { result = ($0, $1) }

        XCTAssertEqual(messaging.registerCallCount, 1)
        XCTAssertNil(result?.fid)
        XCTAssertEqual(result?.error as? TestError, .networkError)
    }

    func testDelegate_whenSet_expectAppMessagingDelegateUntouched() {
        let messaging = FIDMessagingStub()
        FIDMessagingStub.current = messaging
        let delegate = MockFirebaseServiceDelegate()

        firebaseImpl.delegate = delegate

        XCTAssertTrue(firebaseImpl.delegate === delegate)
        XCTAssertEqual(messaging.delegateSetCount, 0)
    }

    func testRegistrationRefreshed_givenFidModeOn_expectRegistration() {
        let messaging = FIDMessagingStub()
        messaging.installationIdEnabled = true
        FIDMessagingStub.current = messaging
        let delegate = MockFirebaseServiceDelegate()
        firebaseImpl.delegate = delegate

        notificationCenter.post(name: .MessagingRegistrationTokenRefreshed, object: "fid")

        XCTAssertEqual(delegate.receivedRegistrations, ["fid"])
        XCTAssertEqual(delegate.tokenCallCount, 0)
    }

    func testRegistrationRefreshed_givenFirebaseWithoutFidRegistration_expectToken() {
        FIDMessagingStub.current = NSObject()
        let delegate = MockFirebaseServiceDelegate()
        firebaseImpl.delegate = delegate

        notificationCenter.post(name: .MessagingRegistrationTokenRefreshed, object: "fcm_token")

        XCTAssertEqual(delegate.receivedToken, "fcm_token")
        XCTAssertTrue(delegate.receivedRegistrations.isEmpty)
    }
}
#endif
