@testable import CioInternalCommon
@testable import CioMessagingInApp
import SharedTests
import XCTest

/// Mock sleeper that returns immediately for fast tests.
private class InstantSleeper: Sleeper {
    var sleepCallCount = 0
    var lastSleepDuration: TimeInterval = 0

    func sleep(seconds: TimeInterval) async throws {
        sleepCallCount += 1
        lastSleepDuration = seconds
        // Return immediately - no actual delay
    }
}

/// Tests for `SseRetryHelper` actor.
class SseRetryHelperTest: XCTestCase {
    private var loggerMock: LoggerMock!
    private var instantSleeper: InstantSleeper!
    private let testGeneration: UInt64 = 1

    override func setUp() {
        super.setUp()
        loggerMock = LoggerMock()
        instantSleeper = InstantSleeper()
    }

    // MARK: - Constants

    func test_constants_expectCorrectValues() {
        XCTAssertEqual(SseRetryHelper.maxRetryCount, 3)
        XCTAssertEqual(SseRetryHelper.retryDelaySeconds, 5.0)
    }

    // MARK: - Retryable Errors

    func test_scheduleRetry_givenRetryableError_firstAttempt_expectImmediateRetry() async {
        let helper = SseRetryHelper(logger: loggerMock, sleeper: instantSleeper)
        let stream = await helper.retryDecisionStream
        var iterator = stream.makeAsyncIterator()

        // Set active generation before scheduling retry
        await helper.setActiveGeneration(testGeneration)

        // Schedule retry with retryable error
        let error = SseError.networkError(message: "Connection failed", underlyingError: nil)
        await helper.scheduleRetry(error: error, generation: testGeneration)

        // Pull the first decision deterministically
        let firstDecision = await iterator.next()

        // First retry should be immediate with attempt count 1
        XCTAssertNotNil(firstDecision)
        XCTAssertEqual(firstDecision?.0, .retryNow(attemptCount: 1))

        // First retry is immediate - no sleep should have been called
        XCTAssertEqual(instantSleeper.sleepCallCount, 0)
    }

    func test_scheduleRetry_givenRetryableError_secondAttempt_expectDelayedRetry() async throws {
        let helper = SseRetryHelper(logger: loggerMock, sleeper: instantSleeper)
        let stream = await helper.retryDecisionStream
        var iterator = stream.makeAsyncIterator()

        // Set active generation before scheduling retry
        await helper.setActiveGeneration(testGeneration)

        let error = SseError.networkError(message: "Connection failed", underlyingError: nil)

        // First retry
        await helper.scheduleRetry(error: error, generation: testGeneration)

        // Pull first decision
        let firstDecision = await iterator.next()
        XCTAssertEqual(firstDecision?.0, .retryNow(attemptCount: 1))

        // Second retry - should use sleeper (but returns instantly in tests)
        await helper.scheduleRetry(error: error, generation: testGeneration)

        // Pull second decision (instant because of mock sleeper)
        let secondDecision = await iterator.next()

        XCTAssertNotNil(secondDecision)
        XCTAssertEqual(secondDecision?.0, .retryNow(attemptCount: 2))

        // Sleeper should have been called for the delayed retry
        XCTAssertEqual(instantSleeper.sleepCallCount, 1)
        XCTAssertEqual(instantSleeper.lastSleepDuration, SseRetryHelper.retryDelaySeconds)
    }

    func test_scheduleRetry_givenMaxRetriesExceeded_expectMaxRetriesReachedDecision() async {
        let helper = SseRetryHelper(logger: loggerMock, sleeper: instantSleeper)
        let stream = await helper.retryDecisionStream
        var iterator = stream.makeAsyncIterator()

        // Set active generation before scheduling retry
        await helper.setActiveGeneration(testGeneration)

        let error = SseError.networkError(message: "Connection failed", underlyingError: nil)

        // Exhaust all retries
        // Attempt 1 (immediate)
        await helper.scheduleRetry(error: error, generation: testGeneration)
        // Attempt 2 (delayed - instant with mock)
        await helper.scheduleRetry(error: error, generation: testGeneration)
        // Attempt 3 (delayed - instant with mock)
        await helper.scheduleRetry(error: error, generation: testGeneration)
        // Attempt 4 - should exceed max
        await helper.scheduleRetry(error: error, generation: testGeneration)

        // Pull decisions until we get maxRetriesReached
        var decisions: [RetryDecision] = []
        while let decision = await iterator.next() {
            decisions.append(decision.0)
            if case .maxRetriesReached = decision.0 {
                break
            }
        }

        // The last decision should be maxRetriesReached
        XCTAssertEqual(decisions.last, .maxRetriesReached)
    }

    // MARK: - Non-Retryable Errors

    func test_scheduleRetry_givenNonRetryableError_expectRetryNotPossible() async {
        let helper = SseRetryHelper(logger: loggerMock, sleeper: instantSleeper)
        let stream = await helper.retryDecisionStream
        var iterator = stream.makeAsyncIterator()

        // Set active generation before scheduling retry
        await helper.setActiveGeneration(testGeneration)

        // Configuration error is not retryable
        let error = SseError.configurationError(message: "Missing user token")
        await helper.scheduleRetry(error: error, generation: testGeneration)

        // Pull the decision
        let decision = await iterator.next()

        XCTAssertNotNil(decision)
        XCTAssertEqual(decision?.0, .retryNotPossible)
    }

    func test_scheduleRetry_givenServerErrorNotRetryable_expectRetryNotPossible() async {
        let helper = SseRetryHelper(logger: loggerMock, sleeper: instantSleeper)
        let stream = await helper.retryDecisionStream
        var iterator = stream.makeAsyncIterator()

        // Set active generation before scheduling retry
        await helper.setActiveGeneration(testGeneration)

        // 401 Unauthorized is not retryable
        let error = SseError.serverError(message: "Unauthorized", responseCode: 401, shouldRetry: false)
        await helper.scheduleRetry(error: error, generation: testGeneration)

        // Pull the decision
        let decision = await iterator.next()

        XCTAssertNotNil(decision)
        XCTAssertEqual(decision?.0, .retryNotPossible)
    }

    // MARK: - Reset State

    func test_resetRetryState_givenRetriesInProgress_expectCountReset() async {
        let helper = SseRetryHelper(logger: loggerMock, sleeper: instantSleeper)
        let stream = await helper.retryDecisionStream
        var iterator = stream.makeAsyncIterator()

        // Set active generation before scheduling retry
        await helper.setActiveGeneration(testGeneration)

        let error = SseError.networkError(message: "Connection failed", underlyingError: nil)

        // Do 2 retries
        await helper.scheduleRetry(error: error, generation: testGeneration)
        await helper.scheduleRetry(error: error, generation: testGeneration)

        // Consume the first 2 decisions
        _ = await iterator.next()
        _ = await iterator.next()

        // Reset state
        await helper.resetRetryState(generation: testGeneration)

        // Now retry again - should start from attempt 1
        await helper.scheduleRetry(error: error, generation: testGeneration)

        let decision = await iterator.next()

        // After reset, first retry should be attempt 1 again
        XCTAssertEqual(decision?.0, .retryNow(attemptCount: 1))
    }

    // MARK: - Timeout Error

    func test_scheduleRetry_givenTimeoutError_expectRetryable() async {
        let helper = SseRetryHelper(logger: loggerMock, sleeper: instantSleeper)
        let stream = await helper.retryDecisionStream
        var iterator = stream.makeAsyncIterator()

        // Set active generation before scheduling retry
        await helper.setActiveGeneration(testGeneration)

        let error = SseError.timeoutError
        await helper.scheduleRetry(error: error, generation: testGeneration)

        let decision = await iterator.next()

        XCTAssertEqual(decision?.0, .retryNow(attemptCount: 1))
    }

    // MARK: - Generation Tests

    func test_scheduleRetry_givenStaleGeneration_expectIgnored() async {
        let helper = SseRetryHelper(logger: loggerMock, sleeper: instantSleeper)
        let stream = await helper.retryDecisionStream
        var iterator = stream.makeAsyncIterator()

        // Set active generation to 2
        await helper.setActiveGeneration(2)

        let error = SseError.networkError(message: "Connection failed", underlyingError: nil)

        // Try to schedule retry with stale generation 1 - should be ignored
        await helper.scheduleRetry(error: error, generation: 1)

        // Schedule retry with correct generation 2
        await helper.scheduleRetry(error: error, generation: 2)

        // Only the second retry (generation 2) should be processed
        let decision = await iterator.next()

        XCTAssertNotNil(decision)
        XCTAssertEqual(decision?.0, .retryNow(attemptCount: 1))
        XCTAssertEqual(decision?.1, 2) // Verify generation is 2
    }

    func test_resetRetryState_givenStaleGeneration_expectIgnored() async {
        let helper = SseRetryHelper(logger: loggerMock, sleeper: instantSleeper)
        let stream = await helper.retryDecisionStream
        var iterator = stream.makeAsyncIterator()

        // Set active generation
        await helper.setActiveGeneration(testGeneration)

        let error = SseError.networkError(message: "Connection failed", underlyingError: nil)

        // Do a retry
        await helper.scheduleRetry(error: error, generation: testGeneration)

        // Consume the first decision
        _ = await iterator.next()

        // Try to reset with wrong generation - should be ignored
        await helper.resetRetryState(generation: 999)

        // Do another retry - should be attempt 2 (not 1) because reset was ignored
        await helper.scheduleRetry(error: error, generation: testGeneration)

        // Pull the decision (instant because of mock sleeper)
        let decision = await iterator.next()

        // Should be attempt 2 because the stale reset was ignored
        XCTAssertEqual(decision?.0, .retryNow(attemptCount: 2))
    }
}
