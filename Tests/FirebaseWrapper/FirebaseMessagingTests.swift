// Moved from customerio/customerio-ios-fcm (Tests/FirebaseMessagingTests.swift). Compiled only with the FCM trait.
#if FCM
@testable import CioFirebaseWrapper
import CioMessagingPushFCM
import FirebaseMessaging
import XCTest

class FirebaseMessagingTests: XCTestCase {
    var mockMessagingDelegate: MockMessagingDelegate!
    var mockFirebaseServiceDelegate: MockFirebaseServiceDelegate!
    var mockFirebaseMessaging: MockFirebaseMessaging!

    override func setUp() {
        super.setUp()

        // Set up Firebase messaging swizzling for testing
        Messaging.swizzleMessaging()

        // Initialize mocks
        mockMessagingDelegate = MockMessagingDelegate()
        mockFirebaseServiceDelegate = MockFirebaseServiceDelegate()
        mockFirebaseMessaging = MockFirebaseMessaging()
    }

    override func tearDown() {
        // Clean up swizzling
        Messaging.unswizzleMessaging()

        mockMessagingDelegate = nil
        mockFirebaseServiceDelegate = nil
        mockFirebaseMessaging = nil

        super.tearDown()
    }

    // MARK: - MockMessagingDelegate Tests

    func testMockMessagingDelegateInitialization() {
        // Given & When
        let delegate = MockMessagingDelegate()

        // Then
        XCTAssertFalse(delegate.didReceiveRegistrationTokenCalled)
        XCTAssertNil(delegate.fcmTokenReceived)
    }

    func testMockMessagingDelegateReceivesToken() {
        // Given
        let expectedToken = TestData.validFCMToken
        let mockMessaging = Messaging.messaging()

        // When
        mockMessagingDelegate.messaging(mockMessaging, didReceiveRegistrationToken: expectedToken)

        // Then
        XCTAssertTrue(mockMessagingDelegate.didReceiveRegistrationTokenCalled)
        XCTAssertEqual(mockMessagingDelegate.fcmTokenReceived, expectedToken)
    }

    func testMockMessagingDelegateReceivesNilToken() {
        // Given
        let mockMessaging = Messaging.messaging()

        // When
        mockMessagingDelegate.messaging(mockMessaging, didReceiveRegistrationToken: nil)

        // Then
        XCTAssertTrue(mockMessagingDelegate.didReceiveRegistrationTokenCalled)
        XCTAssertNil(mockMessagingDelegate.fcmTokenReceived)
    }

    func testMockMessagingDelegateReceivesEmptyToken() {
        // Given
        let emptyToken = TestData.invalidToken
        let mockMessaging = Messaging.messaging()

        // When
        mockMessagingDelegate.messaging(mockMessaging, didReceiveRegistrationToken: emptyToken)

        // Then
        XCTAssertTrue(mockMessagingDelegate.didReceiveRegistrationTokenCalled)
        XCTAssertEqual(mockMessagingDelegate.fcmTokenReceived, emptyToken)
    }

    func testMockMessagingDelegateMultipleTokenUpdates() {
        // Given
        let token1 = "token_1"
        let token2 = "token_2"
        let token3 = "token_3"
        let mockMessaging = Messaging.messaging()

        // When
        mockMessagingDelegate.messaging(mockMessaging, didReceiveRegistrationToken: token1)
        mockMessagingDelegate.messaging(mockMessaging, didReceiveRegistrationToken: token2)
        mockMessagingDelegate.messaging(mockMessaging, didReceiveRegistrationToken: token3)

        // Then
        XCTAssertTrue(mockMessagingDelegate.didReceiveRegistrationTokenCalled)
        XCTAssertEqual(mockMessagingDelegate.fcmTokenReceived, token3)
    }

    // MARK: - MockFirebaseMessaging Tests

    func testMockFirebaseMessagingInitialization() {
        // Given & When
        let mockMessaging = MockFirebaseMessaging()

        // Then
        XCTAssertNil(mockMessaging.mockApnsToken)
        XCTAssertNil(mockMessaging.mockDelegate)
        XCTAssertNil(mockMessaging.tokenCompletion)
        XCTAssertEqual(mockMessaging.tokenCallCount, 0)
    }

    func testMockFirebaseMessagingSimulateTokenSuccess() {
        // Given
        let expectedToken = TestData.validFCMToken
        var receivedToken: String?
        var receivedError: Error?

        mockFirebaseMessaging.tokenCompletion = { token, error in
            receivedToken = token
            receivedError = error
        }

        // When
        mockFirebaseMessaging.simulateTokenSuccess(expectedToken)

        // Then
        XCTAssertEqual(receivedToken, expectedToken)
        XCTAssertNil(receivedError)
    }

    func testMockFirebaseMessagingSimulateTokenError() {
        // Given
        let expectedError = TestError.tokenError
        var receivedToken: String?
        var receivedError: Error?

        mockFirebaseMessaging.tokenCompletion = { token, error in
            receivedToken = token
            receivedError = error
        }

        // When
        mockFirebaseMessaging.simulateTokenError(expectedError)

        // Then
        XCTAssertNil(receivedToken)
        XCTAssertEqual(receivedError as? TestError, expectedError)
    }

    func testMockFirebaseMessagingSimulateRegistrationToken() {
        // Given
        let expectedToken = TestData.validFCMToken
        mockFirebaseMessaging.mockDelegate = mockMessagingDelegate

        // When
        mockFirebaseMessaging.simulateRegistrationToken(expectedToken)

        // Then
        XCTAssertTrue(mockMessagingDelegate.didReceiveRegistrationTokenCalled)
        XCTAssertEqual(mockMessagingDelegate.fcmTokenReceived, expectedToken)
    }

    func testMockFirebaseMessagingSimulateRegistrationTokenWithNilDelegate() {
        // Given
        let expectedToken = TestData.validFCMToken
        mockFirebaseMessaging.mockDelegate = nil

        // When
        mockFirebaseMessaging.simulateRegistrationToken(expectedToken)

        // Then
        // Should not crash and delegate should not be called
        XCTAssertFalse(mockMessagingDelegate.didReceiveRegistrationTokenCalled)
        XCTAssertNil(mockMessagingDelegate.fcmTokenReceived)
    }

    // MARK: - Error Handling Tests

    func testTestErrorEquality() {
        // Given
        let error1 = TestError.networkError
        let error2 = TestError.networkError
        let error3 = TestError.tokenError

        // Then
        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    func testTestDataConstants() {
        // Then
        XCTAssertNotNil(TestData.validApnsToken)
        XCTAssertEqual(TestData.validFCMToken, "valid_fcm_token_12345")
        XCTAssertEqual(TestData.invalidToken, "")
    }

    // MARK: - Integration Tests with Real Firebase Messaging

    func testIntegrationWithRealFirebaseMessaging() {
        // Given
        let realMessaging = Messaging.messaging()
        let expectedToken = TestData.validFCMToken

        // When
        mockMessagingDelegate.messaging(realMessaging, didReceiveRegistrationToken: expectedToken)

        // Then
        XCTAssertTrue(mockMessagingDelegate.didReceiveRegistrationTokenCalled)
        XCTAssertEqual(mockMessagingDelegate.fcmTokenReceived, expectedToken)
    }

    func testIntegrationWithRealFirebaseMessagingNilToken() {
        // Given
        let realMessaging = Messaging.messaging()

        // When
        mockMessagingDelegate.messaging(realMessaging, didReceiveRegistrationToken: nil)

        // Then
        XCTAssertTrue(mockMessagingDelegate.didReceiveRegistrationTokenCalled)
        XCTAssertNil(mockMessagingDelegate.fcmTokenReceived)
    }
}
#endif
