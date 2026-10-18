// Contract: cio-sdk-tools `verify push` reads the `sdk.state` line at each of these triggers, and takes the latest one as
// the SDK's state (its `docs/verify-contract.md`). Dropping a trigger or renaming the line breaks it.

@testable import CioDataPipelines
@testable import CioInternalCommon
@testable import CioInternalCommonMocks
import Foundation
@testable import SharedTests
import XCTest

class DataPipelineSdkStateTests: IntegrationTest {
    private let commonLoggerMock = SdkCommonLoggerMock()

    override open func setUpDependencies() {
        super.setUpDependencies()

        mockCollection.add(mock: commonLoggerMock)
        diGraphShared.override(value: commonLoggerMock, forType: SdkCommonLogger.self)
    }

    // swiftlint:disable:next large_tuple
    private var lastState: (userId: String?, deviceToken: String?, cdpApiKey: String?)? {
        commonLoggerMock.logSdkStateReceivedArguments
    }

    // MARK: init

    func test_init_expectStateLoggedOnce() {
        XCTAssertEqual(commonLoggerMock.logSdkStateCallsCount, 1)
        XCTAssertNil(lastState?.userId)
        XCTAssertNil(lastState?.deviceToken)
        XCTAssertEqual(lastState?.cdpApiKey, dataPipelineConfigOptions.cdpApiKey)
    }

    func test_init_givenIdentityFromLastLaunch_expectRestoredIdentityLogged() {
        customerIO.registerDeviceToken("abcd1234")
        customerIO.identify(userId: "u-42")
        // Analytics persists the identity on the main queue; let that run before the next launch reads it.
        let persisted = expectation(description: "identity persisted")
        DispatchQueue.main.async { persisted.fulfill() }
        wait(for: [persisted], timeout: 1)

        setUp(modifySdkConfig: nil)

        XCTAssertEqual(lastState?.userId, "u-42")
        XCTAssertEqual(lastState?.deviceToken, "abcd1234")
    }

    // MARK: identify

    func test_identify_expectStateLoggedOnceWithUser() {
        commonLoggerMock.resetMock()

        customerIO.identify(userId: "u-42")

        XCTAssertEqual(commonLoggerMock.logSdkStateCallsCount, 1)
        XCTAssertEqual(lastState?.userId, "u-42")
    }

    func test_identify_givenChangingProfile_expectLastLineHasNewUser() {
        customerIO.registerDeviceToken("abcd1234")
        customerIO.identify(userId: "u-1")
        commonLoggerMock.resetMock()

        customerIO.identify(userId: "u-2")

        // The token is deleted from the old profile first, which logs too.
        XCTAssertEqual(commonLoggerMock.logSdkStateCallsCount, 2)
        XCTAssertEqual(lastState?.userId, "u-2")
        XCTAssertEqual(lastState?.deviceToken, "abcd1234")
    }

    // MARK: clearIdentify and reset

    func test_clearIdentify_expectLastLineWithoutUser() {
        customerIO.identify(userId: "u-42")
        commonLoggerMock.resetMock()

        customerIO.clearIdentify()

        // Deleting the token from the profile logs first, then the reset.
        XCTAssertEqual(commonLoggerMock.logSdkStateCallsCount, 2)
        XCTAssertNil(lastState?.userId)
    }

    func test_reset_expectStateLoggedWithoutUser() {
        customerIO.identify(userId: "u-42")
        commonLoggerMock.resetMock()

        customerIO.reset()

        XCTAssertEqual(commonLoggerMock.logSdkStateCallsCount, 1)
        XCTAssertNil(lastState?.userId)
    }

    // MARK: device token

    func test_registerDeviceToken_expectStateLoggedWithToken() {
        customerIO.identify(userId: "u-42")
        commonLoggerMock.resetMock()

        customerIO.registerDeviceToken("abcd1234")

        XCTAssertEqual(commonLoggerMock.logSdkStateCallsCount, 1)
        XCTAssertEqual(lastState?.userId, "u-42")
        XCTAssertEqual(lastState?.deviceToken, "abcd1234")
    }

    func test_registerDeviceToken_givenRefreshedToken_expectEveryLineHasNewToken() {
        customerIO.registerDeviceToken("old-token")
        commonLoggerMock.resetMock()

        customerIO.registerDeviceToken("new-token")

        // The old token is deleted from the profile first, which logs too.
        XCTAssertEqual(commonLoggerMock.logSdkStateReceivedInvocations.map(\.deviceToken), ["new-token", "new-token"])
    }

    func test_deleteDeviceToken_expectStateLogged() {
        customerIO.registerDeviceToken("abcd1234")
        commonLoggerMock.resetMock()

        customerIO.deleteDeviceToken()

        XCTAssertEqual(commonLoggerMock.logSdkStateCallsCount, 1)
        // The token stays stored for the next identify; only the profile loses it.
        XCTAssertEqual(lastState?.deviceToken, "abcd1234")
    }
}
