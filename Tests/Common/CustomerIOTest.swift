@testable import CioInternalCommon
import Foundation
@testable import CioInternalCommonMocks
import SharedTests
import XCTest

class CustomerIOTest: UnitTest {
    private let implmentationMock = CustomerIOInstanceMock()
    private let globalDataStoreMock = GlobalDataStoreMock()

    private var customerIO: CustomerIO!

    override func setUpDependencies() {
        super.setUpDependencies()

        mockCollection.add(mocks: [implmentationMock, globalDataStoreMock])

        diGraphShared.override(value: globalDataStoreMock, forType: GlobalDataStore.self)
    }

    override func initializeSDKComponents() -> CustomerIO? {
        customerIO = CustomerIO.setUpSharedInstanceForUnitTest(implementation: implmentationMock)
        return customerIO
    }

    func test_initialize_givenPushDeviceTokenNotSet_expectRegisterDeviceTokenNotCalled() {
        customerIO.postInitialize(impl: implmentationMock)
        XCTAssertFalse(implmentationMock.registerDeviceTokenCalled)
    }

    func test_initialize_givenPushDeviceTokenSet_expectRegisterDeviceTokenCalled() {
        let pushDeviceToken = String.random
        globalDataStoreMock.pushDeviceToken = pushDeviceToken
        customerIO.postInitialize(impl: implmentationMock)
        XCTAssertTrue(implmentationMock.registerDeviceTokenCalled)
    }

    func test_initializeSharedInstance_givenBufferedRegisterDeviceToken_expectPostInitializeSkipped() {
        // P2 #1 from PR review: when a `registerDeviceToken` is buffered
        // pre-init, postInitialize() must not also register the stored token —
        // otherwise the same device update fires twice.
        let storedToken = String.random
        let bufferedToken = String.random
        let freshImplementation = CustomerIOInstanceMock()
        globalDataStoreMock.pushDeviceToken = storedToken

        CustomerIO.resetSharedTestEnvironment()
        CustomerIO.shared.registerDeviceToken(bufferedToken)

        CustomerIO.initializeSharedInstance(with: freshImplementation)

        XCTAssertEqual(freshImplementation.registerDeviceTokenCallsCount, 1, "exactly one register; postInitialize should skip because a buffered registerDeviceToken is pending")
        XCTAssertEqual(freshImplementation.registerDeviceTokenReceivedArguments, bufferedToken)
    }

    func test_initializeSharedInstance_givenBufferAtCapacityAndDroppedRegisterDeviceToken_expectStoredTokenFallback() {
        // Regression for the drop-and-flag race: if the pre-init buffer is
        // already at capacity when `registerDeviceToken` arrives, the closure
        // is dropped. `hasPendingTokenRegistration` must remain false so
        // `postInitialize` still falls through to registering the stored
        // token. Without that gate, the user's token would be lost *and*
        // postInitialize would skip its fallback, leaving the device
        // unregistered until the next launch.
        let storedToken = String.random
        let droppedToken = String.random
        let freshImplementation = CustomerIOInstanceMock()
        globalDataStoreMock.pushDeviceToken = storedToken

        CustomerIO.resetSharedTestEnvironment()

        // Fill the pre-init buffer to its default capacity (100). Each call
        // routes through `dispatch` → `preInitEventBuffer.enqueue` because
        // `implementation` is nil pre-init.
        for index in 0 ..< 100 {
            CustomerIO.shared.track(name: "preinit_\(index)")
        }
        // This call should hit the capacity ceiling and be dropped; the flag
        // must NOT be set.
        CustomerIO.shared.registerDeviceToken(droppedToken)

        CustomerIO.initializeSharedInstance(with: freshImplementation)

        XCTAssertEqual(freshImplementation.registerDeviceTokenCallsCount, 1, "postInitialize must fall back to the stored token when registerDeviceToken was dropped at capacity")
        XCTAssertEqual(freshImplementation.registerDeviceTokenReceivedArguments, storedToken)
    }

    func test_initializeSharedInstance_givenStoredTokenAndBufferedCall_expectTokenSyncedBeforeReplay() {
        // P2 #1 from PR review: postInitialize() must run before the buffer drain
        // so buffered token-dependent calls (e.g. setDeviceAttributes) observe a
        // non-nil contextPlugin.deviceToken, and a buffered registerDeviceToken
        // is idempotent on an unchanged stored token (verified at the
        // DataPipeline impl level in DataPipelineInteractionTests).
        let storedToken = String.random
        let freshImplementation = CustomerIOInstanceMock()
        globalDataStoreMock.pushDeviceToken = storedToken

        // Reset the singleton to its un-initialized state so we exercise the
        // full pre-init → initialize transition for this test.
        CustomerIO.resetSharedTestEnvironment()

        // Pre-init: enqueue a setDeviceAttributes call onto the buffer.
        CustomerIO.shared.setDeviceAttributes(["any": "value"])
        XCTAssertFalse(freshImplementation.setDeviceAttributesCalled)
        XCTAssertFalse(freshImplementation.registerDeviceTokenCalled)

        // Initialize. Expected order: postInitialize() registers the stored
        // token on the impl → drain replays the buffered setDeviceAttributes
        // against the real implementation → implementation published last so
        // concurrent dispatch calls never race past replay.
        CustomerIO.initializeSharedInstance(with: freshImplementation)

        XCTAssertTrue(freshImplementation.registerDeviceTokenCalled, "postInitialize() should register the stored token before the buffer drains")
        XCTAssertEqual(freshImplementation.registerDeviceTokenReceivedArguments, storedToken)
        XCTAssertTrue(freshImplementation.setDeviceAttributesCalled, "buffered setDeviceAttributes should replay against the real implementation")
    }
}
