@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioMessagingInAppMocks
@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

/// Tests for `SseConnectionManager` actor.
class SseConnectionManagerTest: XCTestCase {
    private var loggerMock: LoggerMock!
    private var inAppMessageManagerMock: InAppMessageManagerMock!
    private var sseServiceMock: SseServiceProtocolMock!
    private var retryHelperMock: SseRetryHelperProtocolMock!
    private var heartbeatTimerMock: HeartbeatTimerProtocolMock!

    private var sut: SseConnectionManager!

    override func setUp() {
        super.setUp()
        loggerMock = LoggerMock()
        inAppMessageManagerMock = InAppMessageManagerMock()
        sseServiceMock = SseServiceProtocolMock()
        retryHelperMock = SseRetryHelperProtocolMock()
        heartbeatTimerMock = HeartbeatTimerProtocolMock()

        // Setup default mock state
        inAppMessageManagerMock.underlyingState = InAppMessageState(
            siteId: "test-site-id",
            dataCenter: "us",
            environment: .production,
            userId: "test-user"
        )

        // Setup empty retry decision stream
        let (stream, _) = AsyncStreamBackport.makeStream(of: (RetryDecision, UInt64).self)
        retryHelperMock.createNewRetryStreamReturnValue = stream

        sut = SseConnectionManager(
            logger: loggerMock,
            inAppMessageManager: inAppMessageManagerMock,
            sseService: sseServiceMock,
            retryHelper: retryHelperMock,
            heartbeatTimer: heartbeatTimerMock
        )
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    /// Waits for an expectation while cooperatively yielding to other tasks.
    /// This ensures spawned tasks get scheduled, unlike XCTest's built-in fulfillment
    /// which may not properly cooperate with Swift concurrency.
    private func waitForExpectation(
        _ exp: XCTestExpectation,
        timeout: TimeInterval = 3.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            // Check if expectation was fulfilled
            let result = XCTWaiter.wait(for: [exp], timeout: 0)
            if result == .completed {
                return
            }
            // Yield to give other tasks a chance to run
            await Task.yield()
        }
        // Final check with real timeout for better error message
        await fulfillment(of: [exp], timeout: 0.1)
    }

    // MARK: - Start Connection Tests

    func test_startConnection_expectSseServiceConnectCalled() async {
        // Setup: SSE service returns a stream that completes immediately
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        continuation.finish()

        // ARM expectation BEFORE triggering SUT (latching pattern)
        let connectCalled = expectation(description: "SSE service connect called")
        sseServiceMock.connectClosure = { [stream] _, _ in
            connectCalled.fulfill()
            return stream
        }

        // Action: startConnection() spawns an internal Task that calls connect()
        await sut.startConnection()

        // Wait for latched signal with cooperative yielding
        await waitForExpectation(connectCalled)

        // Assert
        XCTAssertTrue(sseServiceMock.connectCalled)
        XCTAssertEqual(sseServiceMock.connectCallsCount, 1)
    }

    func test_startConnection_givenAlreadyConnecting_expectNoSecondConnect() async {
        // Setup: SSE service returns a stream that doesn't complete (simulating ongoing connection)
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // ARM: Expect exactly one connect call. Over-fulfill will fail the test if a second call happens.
        let connectCalled = expectation(description: "First connect called")
        connectCalled.expectedFulfillmentCount = 1
        connectCalled.assertForOverFulfill = true
        sseServiceMock.connectClosure = { _, _ in
            connectCalled.fulfill()
            return stream
        }

        // Action: Start connection twice
        await sut.startConnection()
        await waitForExpectation(connectCalled)

        await sut.startConnection()

        // Give any wrongly spawned second connection task time to trigger (if incorrect)
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms observation window

        // Assert: Only one connect call should have happened
        XCTAssertEqual(sseServiceMock.connectCallsCount, 1)
    }

    func test_startConnection_expectHeartbeatCallbackSet() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream
        continuation.finish()

        // ARM expectation before triggering SUT
        let callbackSet = expectation(description: "Heartbeat callback set")
        heartbeatTimerMock.setCallbackClosure = { _ in
            callbackSet.fulfill()
        }

        // Action
        await sut.startConnection()
        await waitForExpectation(callbackSet)

        // Assert
        XCTAssertTrue(heartbeatTimerMock.setCallbackCalled)
    }

    // MARK: - Stop Connection Tests

    func test_stopConnection_expectSseServiceDisconnectCalled() async {
        // Setup: Start a connection first
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // ARM expectation for connect
        let connectCalled = expectation(description: "SSE service connect called")
        sseServiceMock.connectClosure = { _, _ in
            connectCalled.fulfill()
            return stream
        }

        await sut.startConnection()
        await waitForExpectation(connectCalled)

        // Action
        await sut.stopConnection()

        // Assert
        XCTAssertTrue(sseServiceMock.disconnectCalled)
    }

    func test_stopConnection_expectRetryStateReset() async {
        // Setup
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // ARM expectation for connect
        let connectCalled = expectation(description: "SSE service connect called")
        sseServiceMock.connectClosure = { _, _ in
            connectCalled.fulfill()
            return stream
        }

        await sut.startConnection()
        await waitForExpectation(connectCalled)

        // Action
        await sut.stopConnection()

        // Assert
        XCTAssertTrue(retryHelperMock.resetRetryStateCalled)
    }

    func test_stopConnection_expectHeartbeatTimerReset() async {
        // Setup
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // ARM expectation for connect
        let connectCalled = expectation(description: "SSE service connect called")
        sseServiceMock.connectClosure = { _, _ in
            connectCalled.fulfill()
            return stream
        }

        await sut.startConnection()
        await waitForExpectation(connectCalled)

        // Action
        await sut.stopConnection()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.resetCalled)
    }

    // MARK: - Connection Events Tests

    func test_connectionOpen_expectHeartbeatTimerStarted() async {
        // Setup: SSE service returns connectionOpen event
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        // ARM: wait for connect, then for timer start
        let connectCalled = expectation(description: "SSE service connect called")
        sseServiceMock.connectClosure = { [stream] _, _ in
            connectCalled.fulfill()
            return stream
        }

        let timerStarted = expectation(description: "Heartbeat timer started")
        timerStarted.assertForOverFulfill = false // May be called multiple times
        heartbeatTimerMock.startTimerClosure = { _, _ in
            timerStarted.fulfill()
        }

        // Action
        await sut.startConnection()
        await waitForExpectation(connectCalled)

        // Send connectionOpen event
        continuation.yield(.connectionOpen)
        await waitForExpectation(timerStarted)

        // Clean up
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.startTimerCalled)
    }

    // The hook must fire on the SERVER's `connected` event only. setupSuccessfulConnection also runs
    // for the transport `.connectionOpen`, which arrives first, so hooking it there would fire twice
    // and start the first backfill before the server had confirmed anything.
    func test_openThenConnected_expectConnectionConfirmedExactlyOnce() async {
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        // ARM: wait for connect, then for stream finish (reset indicates stream ended)
        let connectCalled = expectation(description: "SSE service connect called")
        sseServiceMock.connectClosure = { [stream] _, _ in
            connectCalled.fulfill()
            return stream
        }

        // Reset can be called multiple times during stream lifecycle
        let streamFinished = expectation(description: "Stream finished")
        streamFinished.assertForOverFulfill = false
        heartbeatTimerMock.resetClosure = { _ in
            streamFinished.fulfill()
        }

        let counter = ConfirmationCounter()
        await sut.setOnConnectionConfirmed { counter.increment() }

        await sut.startConnection()
        await waitForExpectation(connectCalled)

        continuation.yield(.connectionOpen)
        continuation.yield(.serverEvent(ServerEvent(id: nil, type: "connected", data: "")))
        continuation.finish()
        await waitForExpectation(streamFinished)

        XCTAssertEqual(counter.value, 1)
    }

    func test_transportOpenOnly_expectNoConnectionConfirmed() async {
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        // ARM: wait for connect, then for stream finish
        let connectCalled = expectation(description: "SSE service connect called")
        sseServiceMock.connectClosure = { [stream] _, _ in
            connectCalled.fulfill()
            return stream
        }

        // Reset can be called multiple times during stream lifecycle
        let streamFinished = expectation(description: "Stream finished")
        streamFinished.assertForOverFulfill = false
        heartbeatTimerMock.resetClosure = { _ in
            streamFinished.fulfill()
        }

        let counter = ConfirmationCounter()
        await sut.setOnConnectionConfirmed { counter.increment() }

        await sut.startConnection()
        await waitForExpectation(connectCalled)

        continuation.yield(.connectionOpen)
        continuation.finish()
        await waitForExpectation(streamFinished)

        // Transport open alone is not confirmation: nothing should be backfilled yet.
        XCTAssertEqual(counter.value, 0)
    }

    func test_connectionOpen_expectRetryStateReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // ARM: wait for connect, then for retry state reset
        let connectCalled = expectation(description: "SSE service connect called")
        sseServiceMock.connectClosure = { _, _ in
            connectCalled.fulfill()
            return stream
        }

        let retryReset = expectation(description: "Retry state reset")
        retryHelperMock.resetRetryStateClosure = { _ in
            retryReset.fulfill()
        }

        // Action
        await sut.startConnection()
        await waitForExpectation(connectCalled)

        continuation.yield(.connectionOpen)
        await waitForExpectation(retryReset)
        continuation.finish()

        // Assert
        XCTAssertTrue(retryHelperMock.resetRetryStateCalled)
    }

    func test_connectionFailed_givenRetryableError_expectRetryScheduled() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // ARM: wait for connect, then for retry scheduled
        let connectCalled = expectation(description: "SSE service connect called")
        sseServiceMock.connectClosure = { _, _ in
            connectCalled.fulfill()
            return stream
        }

        let error = SseError.networkError(message: "Connection failed", underlyingError: nil)
        let retryScheduled = expectation(description: "Retry scheduled")
        retryHelperMock.scheduleRetryClosure = { receivedError, _ in
            if receivedError == error {
                retryScheduled.fulfill()
            }
        }

        // Action
        await sut.startConnection()
        await waitForExpectation(connectCalled)

        continuation.yield(.connectionFailed(error))
        await waitForExpectation(retryScheduled)
        continuation.finish()

        // Assert
        XCTAssertTrue(retryHelperMock.scheduleRetryCalled)
        XCTAssertEqual(retryHelperMock.scheduleRetryReceivedArguments?.error, error)
    }

    func test_connectionFailed_expectHeartbeatTimerReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        // ARM: wait for connect, then for timer reset
        let connectCalled = expectation(description: "SSE service connect called")
        sseServiceMock.connectClosure = { [stream] _, _ in
            connectCalled.fulfill()
            return stream
        }

        // Reset can be called multiple times (once for event, once when stream finishes)
        let timerReset = expectation(description: "Heartbeat timer reset")
        timerReset.assertForOverFulfill = false
        heartbeatTimerMock.resetClosure = { _ in
            timerReset.fulfill()
        }

        // Action
        await sut.startConnection()
        await waitForExpectation(connectCalled)

        continuation.yield(.connectionFailed(.networkError(message: "Error", underlyingError: nil)))
        await waitForExpectation(timerReset)
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.resetCalled)
    }

    func test_connectionClosed_expectHeartbeatTimerReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        // ARM: wait for connect, then for timer reset
        let connectCalled = expectation(description: "SSE service connect called")
        sseServiceMock.connectClosure = { [stream] _, _ in
            connectCalled.fulfill()
            return stream
        }

        // Reset can be called multiple times (once for event, once when stream finishes)
        let timerReset = expectation(description: "Heartbeat timer reset")
        timerReset.assertForOverFulfill = false
        heartbeatTimerMock.resetClosure = { _ in
            timerReset.fulfill()
        }

        // Action
        await sut.startConnection()
        await waitForExpectation(connectCalled)

        continuation.yield(.connectionClosed)
        await waitForExpectation(timerReset)
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.resetCalled)
    }

    // MARK: - Server Event Tests

    func test_serverEvent_givenConnectedEvent_expectHeartbeatTimerStarted() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // ARM: wait for connect, then for timer start
        let connectCalled = expectation(description: "SSE service connect called")
        sseServiceMock.connectClosure = { _, _ in
            connectCalled.fulfill()
            return stream
        }

        let timerStarted = expectation(description: "Heartbeat timer started")
        heartbeatTimerMock.startTimerClosure = { _, _ in
            timerStarted.fulfill()
        }

        // Action
        await sut.startConnection()
        await waitForExpectation(connectCalled)

        let serverEvent = ServerEvent(id: nil, type: "connected", data: "{}")
        continuation.yield(.serverEvent(serverEvent))
        await waitForExpectation(timerStarted)
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.startTimerCalled)
    }

    func test_serverEvent_givenHeartbeatEvent_expectHeartbeatTimerRestarted() async {
        // Setup
        let (stream, streamContinuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // ARM: wait for connect first
        let connectCalled = expectation(description: "SSE service connect called")
        sseServiceMock.connectClosure = { _, _ in
            connectCalled.fulfill()
            return stream
        }

        // ARM: Set the timer closure before starting the connection.
        // Timer should be called twice: once for connectionOpen, once for heartbeat.
        let heartbeatTimerStartedTwice = expectation(description: "Heartbeat timer started at least twice")
        heartbeatTimerMock.startTimerClosure = { [weak heartbeatTimerMock] _, _ in
            guard let mock = heartbeatTimerMock, mock.startTimerCallsCount == 2 else { return }
            heartbeatTimerStartedTwice.fulfill()
        }

        // Action
        await sut.startConnection()
        await waitForExpectation(connectCalled)

        streamContinuation.yield(.connectionOpen)
        streamContinuation.yield(.serverEvent(ServerEvent(id: nil, type: "heartbeat", data: "{\"heartbeat\": 30}")))
        streamContinuation.finish()

        await waitForExpectation(heartbeatTimerStartedTwice)

        // Assert: Timer started for connection open and again for heartbeat
        XCTAssertGreaterThanOrEqual(heartbeatTimerMock.startTimerCallsCount, 2)
    }

    func test_serverEvent_givenMessagesEvent_expectMessagesDispatched() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        // ARM: wait for connect, then for stream finish
        let connectCalled = expectation(description: "SSE service connect called")
        sseServiceMock.connectClosure = { [stream] _, _ in
            connectCalled.fulfill()
            return stream
        }

        // Reset can be called multiple times during stream lifecycle
        let streamFinished = expectation(description: "Stream finished")
        streamFinished.assertForOverFulfill = false
        heartbeatTimerMock.resetClosure = { _ in
            streamFinished.fulfill()
        }

        inAppMessageManagerMock.dispatchClosure = { _, _ in Task {} }

        // Action
        await sut.startConnection()
        await waitForExpectation(connectCalled)

        // Create a valid messages event with proper JSON
        let messagesJson = """
        [{"queueId": "q1", "priority": 1, "messageId": "m1"}]
        """
        let messagesEvent = ServerEvent(id: nil, type: "messages", data: messagesJson)
        continuation.yield(.serverEvent(messagesEvent))
        continuation.finish()
        await waitForExpectation(streamFinished)

        // Assert: Check if processMessageQueue action was dispatched
        let processActions = inAppMessageManagerMock.dispatchReceivedInvocations.filter {
            if case .processMessageQueue = $0.action { return true }
            return false
        }
        XCTAssertEqual(processActions.count, 1)
    }

    // MARK: - Retry Decision Tests

    func test_retryDecision_givenMaxRetriesReached_expectFallbackToPolling() async {
        // Setup: Create a stream we can emit retry decisions on
        let (retryStream, retryContinuation) = AsyncStreamBackport.makeStream(of: (RetryDecision, UInt64).self)
        retryHelperMock.createNewRetryStreamReturnValue = retryStream

        let (sseStream, sseContinuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = sseStream

        // ARM: wait for connect, then for SSE disable dispatch
        let connectCalled = expectation(description: "SSE service connect called")
        sseServiceMock.connectClosure = { _, _ in
            connectCalled.fulfill()
            return sseStream
        }

        let sseDisabled = expectation(description: "SSE disabled")
        sseDisabled.expectedFulfillmentCount = 1
        sseDisabled.assertForOverFulfill = true
        inAppMessageManagerMock.dispatchClosure = { action, _ in
            if case .setSseEnabled(enabled: false) = action {
                sseDisabled.fulfill()
            }
            return Task {}
        }

        // Create a fresh SUT with the mocked retry stream
        sut = SseConnectionManager(
            logger: loggerMock,
            inAppMessageManager: inAppMessageManagerMock,
            sseService: sseServiceMock,
            retryHelper: retryHelperMock,
            heartbeatTimer: heartbeatTimerMock
        )

        // Action
        await sut.startConnection()
        await waitForExpectation(connectCalled)

        // Emit maxRetriesReached decision (with generation 1)
        retryContinuation.yield((.maxRetriesReached, 1))
        await waitForExpectation(sseDisabled)

        // Observation window: ensure no duplicate dispatch (assertForOverFulfill handles this)
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Clean up
        sseContinuation.finish()
        retryContinuation.finish()

        // Assert: Check that SSE was disabled (fallback to polling)
        let sseDisabledActions = inAppMessageManagerMock.dispatchReceivedInvocations.filter {
            if case .setSseEnabled(enabled: false) = $0.action { return true }
            return false
        }
        XCTAssertEqual(sseDisabledActions.count, 1)
    }

    func test_retryDecision_givenRetryNotPossible_expectFallbackToPolling() async {
        // Setup
        let (retryStream, retryContinuation) = AsyncStreamBackport.makeStream(of: (RetryDecision, UInt64).self)
        retryHelperMock.createNewRetryStreamReturnValue = retryStream

        let (sseStream, sseContinuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = sseStream

        // ARM: wait for connect, then for SSE disable dispatch
        let connectCalled = expectation(description: "SSE service connect called")
        sseServiceMock.connectClosure = { _, _ in
            connectCalled.fulfill()
            return sseStream
        }

        let sseDisabled = expectation(description: "SSE disabled")
        sseDisabled.expectedFulfillmentCount = 1
        sseDisabled.assertForOverFulfill = true
        inAppMessageManagerMock.dispatchClosure = { action, _ in
            if case .setSseEnabled(enabled: false) = action {
                sseDisabled.fulfill()
            }
            return Task {}
        }

        sut = SseConnectionManager(
            logger: loggerMock,
            inAppMessageManager: inAppMessageManagerMock,
            sseService: sseServiceMock,
            retryHelper: retryHelperMock,
            heartbeatTimer: heartbeatTimerMock
        )

        // Action
        await sut.startConnection()
        await waitForExpectation(connectCalled)

        retryContinuation.yield((.retryNotPossible, 1))
        await waitForExpectation(sseDisabled)

        // Observation window
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        sseContinuation.finish()
        retryContinuation.finish()

        // Assert
        let sseDisabledActions = inAppMessageManagerMock.dispatchReceivedInvocations.filter {
            if case .setSseEnabled(enabled: false) = $0.action { return true }
            return false
        }
        XCTAssertEqual(sseDisabledActions.count, 1)
    }
}

/// Counts hook invocations from a `@Sendable` closure. A plain captured `var` is not usable there.
private final class ConfirmationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }
}
