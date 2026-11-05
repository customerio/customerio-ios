import XCTest

// Temporary: checks that a failing test on the second pool is reported red. Do not merge.
final class OverflowBrokenTest: XCTestCase {
    func test_deliberatelyBroken_expectRedOnTheSecondPool() {
        XCTFail("deliberately broken to check that a failure on the second pool is reported red")
    }
}
