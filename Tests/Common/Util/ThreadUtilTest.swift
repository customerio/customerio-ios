@testable import CioInternalCommon
import SharedTests
import XCTest

class ThreadUtilTest: UnitTest {
    func test_runMainActor_expectBlockRunsOnMainThread() {
        let blockExecuted = expectation(description: "main-actor block executed")

        CioThreadUtil().runMainActor {
            XCTAssertTrue(Thread.isMainThread)
            blockExecuted.fulfill()
        }

        wait(for: [blockExecuted], timeout: 1)
    }
}
