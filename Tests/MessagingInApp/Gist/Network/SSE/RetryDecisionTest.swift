@testable import CioMessagingInApp
import XCTest

/// Tests for the `RetryDecision` enum.
class RetryDecisionTest: XCTestCase {
    // MARK: - Equatable

    func test_retryNow_sameAttemptCount_expectEqual() {
        let decision1 = RetryDecision.retryNow(attemptCount: 1)
        let decision2 = RetryDecision.retryNow(attemptCount: 1)

        XCTAssertEqual(decision1, decision2)
    }

    func test_retryNow_differentAttemptCount_expectNotEqual() {
        let decision1 = RetryDecision.retryNow(attemptCount: 1)
        let decision2 = RetryDecision.retryNow(attemptCount: 2)

        XCTAssertNotEqual(decision1, decision2)
    }

    func test_maxRetriesReached_expectEqual() {
        let decision1 = RetryDecision.maxRetriesReached
        let decision2 = RetryDecision.maxRetriesReached

        XCTAssertEqual(decision1, decision2)
    }

    func test_retryNotPossible_expectEqual() {
        let decision1 = RetryDecision.retryNotPossible
        let decision2 = RetryDecision.retryNotPossible

        XCTAssertEqual(decision1, decision2)
    }

    func test_differentDecisionTypes_expectNotEqual() {
        let retryNow = RetryDecision.retryNow(attemptCount: 1)
        let maxRetriesReached = RetryDecision.maxRetriesReached
        let retryNotPossible = RetryDecision.retryNotPossible

        XCTAssertNotEqual(retryNow, maxRetriesReached)
        XCTAssertNotEqual(retryNow, retryNotPossible)
        XCTAssertNotEqual(maxRetriesReached, retryNotPossible)
    }
}
