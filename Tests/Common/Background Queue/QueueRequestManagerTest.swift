@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class QueueRequestManagerTest: UnitTest {
    private var manager: CioQueueRequestManager!

    override func setUp() {
        super.setUp()

        manager = CioQueueRequestManager()
    }

    // MARK: requestComplete

    func test_requestComplete_expectChangeStatusIsRunningARequest() {
        manager.isRunningRequest = true

        manager.requestComplete()

        let actual = manager.startRequest {}
        XCTAssertFalse(actual)
    }

    func test_requestComplete_expectCallCallbacksComplete() {
        var callbackCalled = false
        let givenCallback: () -> Void = {
            callbackCalled = true
        }
        manager.callbacks = [givenCallback]

        manager.requestComplete()

        XCTAssertTrue(callbackCalled)
    }

    // MARK: startRequest

    func test_startRequest_givenNotRunningARequest_expectReturnFalse() {
        let actual = manager.startRequest {}

        XCTAssertFalse(actual)
    }

    func test_startRequest_givenRunningARequest_expectReturnTrue() {
        manager.isRunningRequest = true

        let actual = manager.startRequest {}
        XCTAssertTrue(actual)
    }

    func test_startRequest_expectAddCallback() {
        XCTAssertEqual(manager.callbacks.count, 0)

        _ = manager.startRequest {}

        XCTAssertEqual(manager.callbacks.count, 1)
    }
}
