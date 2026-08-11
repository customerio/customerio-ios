@testable import CioInternalCommon
import SharedTests
import XCTest

private final class LegacyThreadUtil: ThreadUtil {
    private(set) var runBackgroundCallsCount = 0

    func runBackground(_ block: @escaping () -> Void) {
        runBackgroundCallsCount += 1
        block()
    }

    func runMain(_ block: @escaping () -> Void) {
        block()
    }
}

class ThreadUtilTest: UnitTest {
    /// These tests verify queue selection, not dispatch latency. Shared CI runners can delay
    /// low-priority global queues when the full test suite is running concurrently.
    private let queueSchedulingTimeout: TimeInterval = 10

    func test_runMainActor_expectBlockRunsOnMainThread() {
        let blockExecuted = expectation(description: "main-actor block executed")

        CioThreadUtil().runMainActor {
            XCTAssertTrue(Thread.isMainThread)
            blockExecuted.fulfill()
        }

        wait(for: [blockExecuted], timeout: queueSchedulingTimeout)
    }

    func test_runUtility_expectBlockRunsOffMainThread() {
        let blockExecuted = expectation(description: "utility block executed")

        CioThreadUtil().runUtility {
            XCTAssertFalse(Thread.isMainThread)
            blockExecuted.fulfill()
        }

        wait(for: [blockExecuted], timeout: queueSchedulingTimeout)
    }

    func test_defaultScheduling_givenLegacyConformer_expectNewSeamsRemainUsable() {
        let threadUtil = LegacyThreadUtil()
        let mainActorBlockExecuted = expectation(description: "default main-actor block executed")

        threadUtil.runUtility {}
        DispatchQueue.global().async {
            threadUtil.runMainActor {
                XCTAssertTrue(Thread.isMainThread)
                mainActorBlockExecuted.fulfill()
            }
        }

        wait(for: [mainActorBlockExecuted], timeout: queueSchedulingTimeout)
        XCTAssertEqual(threadUtil.runBackgroundCallsCount, 1)
    }
}
