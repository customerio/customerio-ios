// Moved from customerio/customerio-ios-fcm (Tests/FirebaseRegistrationObserverTests.swift). Compiled only with the FCM trait.
#if FCM
@testable import CioFirebaseWrapper
import FirebaseMessaging
import XCTest

class FirebaseRegistrationObserverTests: XCTestCase {
    private var notificationCenter: NotificationCenter!
    private var observer: FirebaseRegistrationObserver!
    private var mockDelegate: MockFirebaseServiceDelegate!

    override func setUp() {
        super.setUp()

        notificationCenter = NotificationCenter()
        mockDelegate = MockFirebaseServiceDelegate()
        observer = FirebaseRegistrationObserver(notificationCenter: notificationCenter)
        observer.delegate = mockDelegate
    }

    override func tearDown() {
        observer = nil
        mockDelegate = nil
        notificationCenter = nil

        super.tearDown()
    }

    func testRegistrationRefreshed_givenTokenMode_expectToken() {
        notificationCenter.post(name: .MessagingRegistrationTokenRefreshed, object: "fcm_token")

        XCTAssertEqual(mockDelegate.receivedToken, "fcm_token")
        XCTAssertEqual(mockDelegate.tokenCallCount, 1)
        XCTAssertTrue(mockDelegate.receivedRegistrations.isEmpty)
    }

    func testRegistrationRefreshed_givenFidMode_expectRegistration() {
        observer.isInstallationIdEnabled = { true }

        notificationCenter.post(name: .MessagingRegistrationTokenRefreshed, object: "fid")

        XCTAssertEqual(mockDelegate.receivedRegistrations, ["fid"])
        XCTAssertEqual(mockDelegate.tokenCallCount, 0)
    }

    func testRegistrationRefreshed_givenNoValue_expectNilForwarded() {
        notificationCenter.post(name: .MessagingRegistrationTokenRefreshed, object: nil)

        XCTAssertNil(mockDelegate.receivedToken)
        XCTAssertEqual(mockDelegate.tokenCallCount, 1)
    }

    func testRegistrationRefreshed_givenNoDelegate_expectNothingForwarded() {
        observer.delegate = nil

        notificationCenter.post(name: .MessagingRegistrationTokenRefreshed, object: "fcm_token")

        XCTAssertEqual(mockDelegate.tokenCallCount, 0)
    }
}
#endif
