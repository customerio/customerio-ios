@testable import CioInternalCommon
@testable import CioMessagingPush
@testable import CioMessagingPushMocks
import SharedTests
import XCTest

class MessagingPushRegisterDeviceTokenTest: UnitTest {
    // The real implementation only posts an event; DataPipeline stores the token later. The mock never stores it.
    private let implementationMock = MessagingPushInstanceMock()

    override func initializeSDKComponents() -> MessagingPushInstance? {
        MessagingPush.setUpSharedInstanceForUnitTest(
            implementation: implementationMock,
            diGraphShared: diGraphShared,
            config: messagingPushConfigOptions
        )
        return implementationMock
    }

    func test_registerDeviceToken_whenSameNewTokenTwice_thenRegisteredOnce() {
        MessagingPush.shared.registerDeviceToken("new-token")
        MessagingPush.shared.registerDeviceToken("new-token")

        XCTAssertEqual(implementationMock.registerDeviceTokenReceivedInvocations, ["new-token"])
    }

    func test_registerDeviceToken_whenTokenChangesAndChangesBack_thenEachChangeIsRegistered() {
        MessagingPush.shared.registerDeviceToken("token-1")
        MessagingPush.shared.registerDeviceToken("token-2")
        MessagingPush.shared.registerDeviceToken("token-1")

        XCTAssertEqual(implementationMock.registerDeviceTokenReceivedInvocations, ["token-1", "token-2", "token-1"])
    }

    func test_registerDeviceToken_whenSameNewTokenFromManyThreads_thenRegisteredOnce() {
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            MessagingPush.shared.registerDeviceToken("new-token")
        }

        XCTAssertEqual(implementationMock.registerDeviceTokenReceivedInvocations, ["new-token"])
    }

    // e.g. the app also called CustomerIO.shared.registerDeviceToken with another token
    func test_registerDeviceToken_whenStoredTokenChangedElsewhere_thenSameTokenIsRegisteredAgain() {
        var globalDataStore = diGraphShared.globalDataStore
        MessagingPush.shared.registerDeviceToken("token-1")
        globalDataStore.pushDeviceToken = "token-2"

        MessagingPush.shared.registerDeviceToken("token-1")

        XCTAssertEqual(implementationMock.registerDeviceTokenReceivedInvocations, ["token-1", "token-1"])
    }

    // The implementation stores the token once it's registered, so it isn't stored here.
    func test_registerDeviceToken_whenImplementationIsSet_thenStoredTokenIsUnchanged() {
        var globalDataStore = diGraphShared.globalDataStore
        globalDataStore.pushDeviceToken = "old-token"

        MessagingPush.shared.registerDeviceToken("new-token")

        XCTAssertEqual(diGraphShared.globalDataStore.pushDeviceToken, "old-token")
    }

    func test_registerDeviceToken_whenTokenIsAlreadyStored_thenNotRegistered() {
        var globalDataStore = diGraphShared.globalDataStore
        globalDataStore.pushDeviceToken = "token"

        MessagingPush.shared.registerDeviceToken("token")

        XCTAssertFalse(implementationMock.registerDeviceTokenCalled)
    }
}
