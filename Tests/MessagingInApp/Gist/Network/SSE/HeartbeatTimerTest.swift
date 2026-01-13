@testable import CioInternalCommon
@testable import CioMessagingInApp
import SharedTests
import XCTest

class HeartbeatTimerTest: XCTestCase {
    private var loggerMock: LoggerMock!

    override func setUp() {
        super.setUp()
        loggerMock = LoggerMock()
    }

    // MARK: - Constants

    func test_constants_expectCorrectValues() {
        XCTAssertEqual(HeartbeatTimer.defaultHeartbeatTimeoutSeconds, 30)
        XCTAssertEqual(HeartbeatTimer.heartbeatBufferSeconds, 5)
        XCTAssertEqual(HeartbeatTimer.initialTimeoutSeconds, 35)
    }

    // MARK: - Timer Start/Reset

    func test_startTimer_expectTimerStarts() async {
        var timeoutCalled = false
        let timer = HeartbeatTimer(logger: loggerMock)
        await timer.setCallback { _ in
            timeoutCalled = true
        }

        await timer.startTimer(timeoutSeconds: 100, generation: 1)

        // Timer should not fire immediately
        XCTAssertFalse(timeoutCalled)

        // Cleanup
        await timer.reset(generation: 1)
    }

    func test_reset_givenTimerRunning_expectTimerCancelled() async throws {
        var timeoutCalled = false
        let timer = HeartbeatTimer(logger: loggerMock)
        await timer.setCallback { _ in
            timeoutCalled = true
        }

        // Start timer with short timeout
        await timer.startTimer(timeoutSeconds: 0.1, generation: 1)

        // Reset before it fires
        await timer.reset(generation: 1)

        // Wait longer than the timeout
        try await Task.sleep(nanoseconds: 200000000) // 0.2 seconds

        // Timeout should not have been called because we reset
        XCTAssertFalse(timeoutCalled)
    }

    func test_startTimer_givenMultipleStarts_expectPreviousTimerCancelled() async throws {
        var timeoutCount = 0
        let timer = HeartbeatTimer(logger: loggerMock)
        await timer.setCallback { _ in
            timeoutCount += 1
        }

        // Start timer with very short timeout
        await timer.startTimer(timeoutSeconds: 0.05, generation: 1)

        // Immediately start another timer with longer timeout
        await timer.startTimer(timeoutSeconds: 0.5, generation: 1)

        // Wait for first timer's timeout to pass
        try await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // First timer should have been cancelled, so timeout count should still be 0
        XCTAssertEqual(timeoutCount, 0)

        // Cleanup
        await timer.reset(generation: 1)
    }

    func test_timer_givenTimeoutExpires_expectCallbackInvoked() async throws {
        let expectation = XCTestExpectation(description: "Timeout callback invoked")
        var timeoutCalled = false

        let timer = HeartbeatTimer(logger: loggerMock)
        await timer.setCallback { _ in
            timeoutCalled = true
            expectation.fulfill()
        }

        // Start timer with very short timeout
        await timer.startTimer(timeoutSeconds: 0.05, generation: 1)

        // Wait for timeout
        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertTrue(timeoutCalled)
    }

    func test_reset_givenNoTimerRunning_expectNoError() async {
        let timer = HeartbeatTimer(logger: loggerMock)

        // Should not throw or crash
        await timer.reset(generation: 1)
        await timer.reset(generation: 1)
    }

    // MARK: - Generation Tests

    func test_reset_givenDifferentGeneration_expectTimerNotCancelled() async throws {
        let expectation = XCTestExpectation(description: "Timeout callback invoked")
        var timeoutCalled = false

        let timer = HeartbeatTimer(logger: loggerMock)
        await timer.setCallback { _ in
            timeoutCalled = true
            expectation.fulfill()
        }

        // Start timer with generation 2
        await timer.startTimer(timeoutSeconds: 0.05, generation: 2)

        // Try to reset with generation 1 (should be ignored)
        await timer.reset(generation: 1)

        // Wait for timeout - should still fire because reset was for wrong generation
        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertTrue(timeoutCalled)
    }

    func test_staleTimer_givenNewGeneration_expectCallbackIgnored() async throws {
        var callbackGeneration: UInt64 = 0
        let expectation = XCTestExpectation(description: "Timeout callback invoked")

        let timer = HeartbeatTimer(logger: loggerMock)
        await timer.setCallback { generation in
            callbackGeneration = generation
            expectation.fulfill()
        }

        // Start timer with generation 1
        await timer.startTimer(timeoutSeconds: 0.05, generation: 1)

        // Immediately start new timer with generation 2 (simulating new connection)
        await timer.startTimer(timeoutSeconds: 0.05, generation: 2)

        // Wait for timeout
        await fulfillment(of: [expectation], timeout: 1.0)

        // Only generation 2 callback should have fired
        XCTAssertEqual(callbackGeneration, 2)
    }
}
