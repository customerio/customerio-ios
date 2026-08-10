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
        DispatchQueue.main.async(execute: block)
    }
}

class ThreadUtilTest: UnitTest {
    func test_runMainActor_expectBlockRunsOnMainThread() {
        let blockExecuted = expectation(description: "main-actor block executed")

        CioThreadUtil().runMainActor {
            XCTAssertTrue(Thread.isMainThread)
            blockExecuted.fulfill()
        }

        wait(for: [blockExecuted], timeout: 1)
    }

    func test_runUtility_expectBlockRunsOffMainThread() {
        let blockExecuted = expectation(description: "utility block executed")

        CioThreadUtil().runUtility {
            XCTAssertFalse(Thread.isMainThread)
            blockExecuted.fulfill()
        }

        wait(for: [blockExecuted], timeout: 1)
    }

    func test_defaultScheduling_givenLegacyConformer_expectNewSeamsRemainUsable() {
        let threadUtil = LegacyThreadUtil()
        let mainActorBlockExecuted = expectation(description: "default main-actor block executed")

        threadUtil.runUtility {}
        threadUtil.runMainActor {
            mainActorBlockExecuted.fulfill()
        }

        wait(for: [mainActorBlockExecuted], timeout: 1)
        XCTAssertEqual(threadUtil.runBackgroundCallsCount, 1)
    }
}
