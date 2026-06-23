@testable import CioInternalCommon
@testable import CioMessagingInApp
@testable import CioMessagingInAppMocks
import Foundation
import XCTest

class InboxFetchRetryTest: XCTestCase {
    private var sleeperMock: SleeperMock!
    private var logger: Logger!

    override func setUp() {
        super.setUp()
        sleeperMock = SleeperMock()
        sleeperMock.sleepClosure = { _ in } // no real delay
        logger = DIGraphShared.shared.logger
    }

    // MARK: - Policy math

    func test_policyDelay_expectExponentialBackoff() {
        let policy = InboxRetryPolicy(baseDelay: 0.5, multiplier: 2.0, maxAttempts: 4)

        XCTAssertEqual(policy.delay(afterAttempt: 0), 0.5, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(afterAttempt: 1), 1.0, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(afterAttempt: 2), 2.0, accuracy: 0.0001)
    }

    // MARK: - Success / retry behavior

    func test_run_whenSucceedsFirstTry_expectNoSleepNoRetry() async throws {
        let retrier = InboxFetchRetrier(
            policy: InboxRetryPolicy(baseDelay: 0.1, multiplier: 2, maxAttempts: 3),
            sleeper: sleeperMock,
            logger: logger
        )

        var attempts = 0
        let result = try await retrier.run(label: "t") {
            attempts += 1
            return "ok"
        }

        XCTAssertEqual(result, "ok")
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(sleeperMock.sleepCallsCount, 0)
    }

    func test_run_whenFailsThenSucceeds_expectRetryWithBackoffSleep() async throws {
        let retrier = InboxFetchRetrier(
            policy: InboxRetryPolicy(baseDelay: 0.5, multiplier: 2, maxAttempts: 3),
            sleeper: sleeperMock,
            logger: logger
        )

        var attempts = 0
        let result = try await retrier.run(label: "t") {
            attempts += 1
            if attempts < 2 {
                throw InboxNetworkError.httpStatus(500)
            }
            return "recovered"
        }

        XCTAssertEqual(result, "recovered")
        XCTAssertEqual(attempts, 2)
        // One sleep between the failed attempt and the retry.
        XCTAssertEqual(sleeperMock.sleepCallsCount, 1)
        XCTAssertEqual(sleeperMock.sleepReceivedArguments, 0.5)
    }

    func test_run_whenAllAttemptsFail_expectThrowsLastErrorAfterMaxAttempts() async {
        let retrier = InboxFetchRetrier(
            policy: InboxRetryPolicy(baseDelay: 0.1, multiplier: 2, maxAttempts: 3),
            sleeper: sleeperMock,
            logger: logger
        )

        var attempts = 0
        do {
            _ = try await retrier.run(label: "t") { () throws -> String in
                attempts += 1
                throw InboxNetworkError.httpStatus(503)
            }
            XCTFail("Expected error to be thrown after retries exhausted")
        } catch {
            XCTAssertEqual(error as? InboxNetworkError, .httpStatus(503))
        }

        XCTAssertEqual(attempts, 3) // initial + 2 retries
        // Sleeps happen between attempts only (not after the last).
        XCTAssertEqual(sleeperMock.sleepCallsCount, 2)
    }
}
