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
        await timer.setCallback {
            timeoutCalled = true
        }

        await timer.startTimer(timeoutSeconds: 100)

        // Timer should not fire immediately
        XCTAssertFalse(timeoutCalled)

        // Cleanup
        await timer.reset()
    }

    func test_reset_givenTimerRunning_expectTimerCancelled() async throws {
        var timeoutCalled = false
        let timer = HeartbeatTimer(logger: loggerMock)
        await timer.setCallback {
            timeoutCalled = true
        }

        // Start timer with short timeout
        await timer.startTimer(timeoutSeconds: 0.1)

        // Reset before it fires
        await timer.reset()

        // Wait longer than the timeout
        try await Task.sleep(nanoseconds: 200000000) // 0.2 seconds

        // Timeout should not have been called because we reset
        XCTAssertFalse(timeoutCalled)
    }

    func test_startTimer_givenMultipleStarts_expectPreviousTimerCancelled() async throws {
        var timeoutCount = 0
        let timer = HeartbeatTimer(logger: loggerMock)
        await timer.setCallback {
            timeoutCount += 1
        }

        // Start timer with very short timeout
        await timer.startTimer(timeoutSeconds: 0.05)

        // Immediately start another timer with longer timeout
        await timer.startTimer(timeoutSeconds: 0.5)

        // Wait for first timer's timeout to pass
        try await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // First timer should have been cancelled, so timeout count should still be 0
        XCTAssertEqual(timeoutCount, 0)

        // Cleanup
        await timer.reset()
    }

    func test_timer_givenTimeoutExpires_expectCallbackInvoked() async throws {
        let expectation = XCTestExpectation(description: "Timeout callback invoked")
        var timeoutCalled = false

        let timer = HeartbeatTimer(logger: loggerMock)
        await timer.setCallback {
            timeoutCalled = true
            expectation.fulfill()
        }

        // Start timer with very short timeout
        await timer.startTimer(timeoutSeconds: 0.05)

        // Wait for timeout
        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertTrue(timeoutCalled)
    }

    func test_reset_givenNoTimerRunning_expectNoError() async {
        let timer = HeartbeatTimer(logger: loggerMock)

        // Should not throw or crash
        await timer.reset()
        await timer.reset()
    }
}
