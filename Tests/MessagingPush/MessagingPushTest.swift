@testable import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class MessagingPushTest: UnitTest {
    let sdkInitializedUtilMock = SdkInitializedUtilMock()
    let implementationMock = MessagingPushInstanceMock()
    var messagingPush: MessagingPush!

    func test_createImplementation_givenSdkNotInitialized_expectIgnoreCalls() {
        setupTest(isSdkInitialized: false)

        messagingPush.registerDeviceToken(String.random)

        XCTAssertFalse(didSuccessfullyMakeSdkCall())
    }

    func test_createImplementation_givenSdkInitialized_expectCreateInstanceOnce() {
        setupTest(isSdkInitialized: true)

        messagingPush.registerDeviceToken(String.random)

        XCTAssertTrue(didSuccessfullyMakeSdkCall())
    }
}

extension MessagingPushTest {
    private func setupTest(isSdkInitialized: Bool) {
        sdkInitializedUtilMock.underlyingIsInitlaized = isSdkInitialized

        if isSdkInitialized {
            sdkInitializedUtilMock.underlyingPostInitializedData = (siteId: testSiteId, diGraph: diGraph)
        }

        messagingPush = MessagingPush(implementation: implementationMock, sdkInitializedUtil: sdkInitializedUtilMock)
    }

    private func didSuccessfullyMakeSdkCall() -> Bool {
        implementationMock.mockCalled
    }
}
