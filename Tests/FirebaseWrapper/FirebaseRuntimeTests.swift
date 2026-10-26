@testable import CioFirebaseWrapper
import XCTest

class FirebaseRuntimeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TokenOnlyMessagingStub.current = TokenOnlyMessagingStub()
        TokenOnlyMessagingStub.messagingCallCount = 0
        FirebaseAppStub.isConfigured = false
    }

    private func runtime(firebaseAppClassName: String = "CioTestFirebaseApp") -> FirebaseRuntime {
        FirebaseRuntime(messagingClassName: "CioTestTokenOnlyMessaging", installationsClassName: "CioTestInstallations", firebaseAppClassName: firebaseAppClassName)
    }

    func test_messaging_givenDefaultAppNotConfigured_expectNilWithoutAskingMessaging() {
        let runtime = runtime()

        XCTAssertEqual(runtime.isDefaultAppConfigured, false)
        XCTAssertNil(runtime.messaging())
        // `+[FIRMessaging messaging]` logs an error while Firebase isn't configured, so it isn't called.
        XCTAssertEqual(TokenOnlyMessagingStub.messagingCallCount, 0)
    }

    func test_messaging_givenDefaultAppConfigured_expectMessaging() {
        FirebaseAppStub.isConfigured = true
        let runtime = runtime()

        XCTAssertEqual(runtime.isDefaultAppConfigured, true)
        XCTAssertTrue(runtime.messaging() as AnyObject === TokenOnlyMessagingStub.current)
    }

    func test_isDefaultAppConfigured_givenFirebaseCoreCantTell_expectNilAndMessagingAsked() {
        let runtime = runtime(firebaseAppClassName: "CioTestMissingFirebaseApp")

        XCTAssertNil(runtime.isDefaultAppConfigured)
        XCTAssertNotNil(runtime.messaging())
        XCTAssertEqual(TokenOnlyMessagingStub.messagingCallCount, 1)
    }
}
