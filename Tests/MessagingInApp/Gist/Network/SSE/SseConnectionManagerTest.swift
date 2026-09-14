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
        // Clear all mock closures to avoid retention cycles
        sseServiceMock.connectClosure = nil
        heartbeatTimerMock.setCallbackClosure = nil
        heartbeatTimerMock.startTimerClosure = nil
        heartbeatTimerMock.resetClosure = nil
        retryHelperMock.resetRetryStateClosure = nil
        retryHelperMock.scheduleRetryClosure = nil
        inAppMessageManagerMock.dispatchClosure = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Start Connection Tests

    func test_startConnection_expectSseServiceConnectCalled() async {
        // Setup: SSE service returns a stream that completes immediately
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let connectExpectation = expectation(description: "SSE service connect called")
        sseServiceMock.connectClosure = { _, _ in
            connectExpectation.fulfill()
            return stream
        }

        // Action
        await sut.startConnection()
        continuation.finish()

        await fulfillment(of: [connectExpectation], timeout: 1.0)

        // Assert
        XCTAssertTrue(sseServiceMock.connectCalled)
        XCTAssertEqual(sseServiceMock.connectCallsCount, 1)
    }

    func test_startConnection_givenAlreadyConnecting_expectNoSecondConnect() async {
        // Setup: SSE service returns a stream that doesn't complete (simulating ongoing connection)
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        let connectExpectation = expectation(description: "First connect called")
        connectExpectation.expectedFulfillmentCount = 1
        // Use assertForOverFulfill to detect if a second connect happens
        connectExpectation.assertForOverFulfill = true

        sseServiceMock.connectClosure = { _, _ in
            connectExpectation.fulfill()
            return stream
        }

        // Action: Start connection twice
        await sut.startConnection()
        await fulfillment(of: [connectExpectation], timeout: 2.0)

        await sut.startConnection()

        // Give any wrongly spawned connection task time to trigger (it won't if correct)
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms observation window

        // Assert: Only one connect call
        XCTAssertEqual(sseServiceMock.connectCallsCount, 1)
    }

    func test_startConnection_expectHeartbeatCallbackSet() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let callbackExpectation = expectation(description: "Heartbeat callback set")
        heartbeatTimerMock.setCallbackClosure = { _ in
            callbackExpectation.fulfill()
        }

        // Action
        await sut.startConnection()
        continuation.finish()

        await fulfillment(of: [callbackExpectation], timeout: 1.0)

        // Assert
        XCTAssertTrue(heartbeatTimerMock.setCallbackCalled)
    }

    // MARK: - Stop Connection Tests

    func test_stopConnection_expectSseServiceDisconnectCalled() async {
        // Setup: Start a connection first
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let connectExpectation = expectation(description: "Connect called")
        sseServiceMock.connectClosure = { _, _ in
            connectExpectation.fulfill()
            return stream
        }

        await sut.startConnection()
        await fulfillment(of: [connectExpectation], timeout: 1.0)

        // Action
        await sut.stopConnection()

        // Assert
        XCTAssertTrue(sseServiceMock.disconnectCalled)
    }

    func test_stopConnection_expectRetryStateReset() async {
        // Setup
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let connectExpectation = expectation(description: "Connect called")
        sseServiceMock.connectClosure = { _, _ in
            connectExpectation.fulfill()
            return stream
        }

        await sut.startConnection()
        await fulfillment(of: [connectExpectation], timeout: 1.0)

        // Action
        await sut.stopConnection()

        // Assert
        XCTAssertTrue(retryHelperMock.resetRetryStateCalled)
    }

    func test_stopConnection_expectHeartbeatTimerReset() async {
        // Setup
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let connectExpectation = expectation(description: "Connect called")
        sseServiceMock.connectClosure = { _, _ in
            connectExpectation.fulfill()
            return stream
        }

        await sut.startConnection()
        await fulfillment(of: [connectExpectation], timeout: 1.0)

        // Action
        await sut.stopConnection()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.resetCalled)
    }

    // MARK: - Connection Events Tests

    func test_connectionOpen_expectHeartbeatTimerStarted() async {
        // Setup: SSE service returns connectionOpen event
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let timerStartedExpectation = expectation(description: "Heartbeat timer started")
        heartbeatTimerMock.startTimerClosure = { _, _ in
            timerStartedExpectation.fulfill()
        }

        // Action
        await sut.startConnection()

        // Give the spawned task time to start iterating the stream
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // Send connectionOpen event
        continuation.yield(.connectionOpen)
        await fulfillment(of: [timerStartedExpectation], timeout: 2.0)

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
        sseServiceMock.connectReturnValue = stream

        let counter = ConfirmationCounter()
        await sut.setOnConnectionConfirmed { counter.increment() }

        let resetExpectation = expectation(description: "Stream finished and reset called")
        heartbeatTimerMock.resetClosure = { _ in
            resetExpectation.fulfill()
        }

        await sut.startConnection()

        // Give the spawned task time to start iterating the stream
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        continuation.yield(.connectionOpen)
        continuation.yield(.serverEvent(ServerEvent(id: nil, type: "connected", data: "")))
        continuation.finish()

        await fulfillment(of: [resetExpectation], timeout: 2.0)

        XCTAssertEqual(counter.value, 1)
    }

    func test_transportOpenOnly_expectNoConnectionConfirmed() async {
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let counter = ConfirmationCounter()
        await sut.setOnConnectionConfirmed { counter.increment() }

        let resetExpectation = expectation(description: "Stream finished and reset called")
        heartbeatTimerMock.resetClosure = { _ in
            resetExpectation.fulfill()
        }

        await sut.startConnection()

        // Give the spawned task time to start iterating the stream
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        continuation.yield(.connectionOpen)
        continuation.finish()

        await fulfillment(of: [resetExpectation], timeout: 2.0)

        // Transport open alone is not confirmation: nothing should be backfilled yet.
        XCTAssertEqual(counter.value, 0)
    }

    func test_connectionOpen_expectRetryStateReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let retryResetExpectation = expectation(description: "Retry state reset")
        retryHelperMock.resetRetryStateClosure = { _ in
            retryResetExpectation.fulfill()
        }

        // Action
        await sut.startConnection()

        // Give the spawned task time to start iterating the stream
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        continuation.yield(.connectionOpen)

        await fulfillment(of: [retryResetExpectation], timeout: 2.0)
        continuation.finish()

        // Assert
        XCTAssertTrue(retryHelperMock.resetRetryStateCalled)
    }

    func test_connectionFailed_givenRetryableError_expectRetryScheduled() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let error = SseError.networkError(message: "Connection failed", underlyingError: nil)

        let retryScheduledExpectation = expectation(description: "Retry scheduled")
        retryHelperMock.scheduleRetryClosure = { receivedError, _ in
            if receivedError == error {
                retryScheduledExpectation.fulfill()
            }
        }

        // Action
        await sut.startConnection()

        // Give the spawned task time to start iterating the stream
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        continuation.yield(.connectionFailed(error))

        await fulfillment(of: [retryScheduledExpectation], timeout: 2.0)
        continuation.finish()

        // Assert
        XCTAssertTrue(retryHelperMock.scheduleRetryCalled)
        XCTAssertEqual(retryHelperMock.scheduleRetryReceivedArguments?.error, error)
    }

    func test_connectionFailed_expectHeartbeatTimerReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let resetExpectation = expectation(description: "Heartbeat timer reset")
        heartbeatTimerMock.resetClosure = { _ in
            resetExpectation.fulfill()
        }

        // Action
        await sut.startConnection()

        // Give the spawned task time to start iterating the stream
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        continuation.yield(.connectionFailed(.networkError(message: "Error", underlyingError: nil)))

        await fulfillment(of: [resetExpectation], timeout: 2.0)
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.resetCalled)
    }

    func test_connectionClosed_expectHeartbeatTimerReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let resetExpectation = expectation(description: "Heartbeat timer reset")
        heartbeatTimerMock.resetClosure = { _ in
            resetExpectation.fulfill()
        }

        // Action
        await sut.startConnection()

        // Give the spawned task time to start iterating the stream
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        continuation.yield(.connectionClosed)

        await fulfillment(of: [resetExpectation], timeout: 2.0)
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.resetCalled)
    }

    // MARK: - Server Event Tests

    func test_serverEvent_givenConnectedEvent_expectHeartbeatTimerStarted() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let timerStartedExpectation = expectation(description: "Heartbeat timer started")
        heartbeatTimerMock.startTimerClosure = { _, _ in
            timerStartedExpectation.fulfill()
        }

        // Action
        await sut.startConnection()

        // Give the spawned task time to start iterating the stream
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        let serverEvent = ServerEvent(id: nil, type: "connected", data: "{}")
        continuation.yield(.serverEvent(serverEvent))

        await fulfillment(of: [timerStartedExpectation], timeout: 2.0)
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.startTimerCalled)
    }

    func test_serverEvent_givenHeartbeatEvent_expectHeartbeatTimerRestarted() async {
        // Setup
        let (stream, streamContinuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // Track timer starts with a thread-safe counter
        let timerStartCount = AtomicCounter()
        let timerStartedTwice = expectation(description: "Heartbeat timer started at least twice")

        heartbeatTimerMock.startTimerClosure = { _, _ in
            let count = timerStartCount.increment()
            if count >= 2 {
                timerStartedTwice.fulfill()
            }
        }

        // Action
        await sut.startConnection()

        // Give the spawned task time to start iterating the stream
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        streamContinuation.yield(.connectionOpen)
        streamContinuation.yield(.serverEvent(ServerEvent(id: nil, type: "heartbeat", data: "{\"heartbeat\": 30}")))
        streamContinuation.finish()

        await fulfillment(of: [timerStartedTwice], timeout: 2.0)

        // Assert: Timer started for connection open and again for heartbeat
        XCTAssertGreaterThanOrEqual(heartbeatTimerMock.startTimerCallsCount, 2)
    }

    func test_serverEvent_givenMessagesEvent_expectMessagesDispatched() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let dispatchExpectation = expectation(description: "Process message queue dispatched")
        inAppMessageManagerMock.dispatchClosure = { action, _ in
            if case .processMessageQueue = action {
                dispatchExpectation.fulfill()
            }
            return Task {}
        }

        // Also wait for stream finish
        let resetExpectation = expectation(description: "Stream finished")
        heartbeatTimerMock.resetClosure = { _ in
            resetExpectation.fulfill()
        }

        // Action
        await sut.startConnection()

        // Give the spawned task time to start iterating the stream
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // Create a valid messages event with proper JSON
        let messagesJson = """
        [{"queueId": "q1", "priority": 1, "messageId": "m1"}]
        """
        let messagesEvent = ServerEvent(id: nil, type: "messages", data: messagesJson)
        continuation.yield(.serverEvent(messagesEvent))
        continuation.finish()

        await fulfillment(of: [dispatchExpectation, resetExpectation], timeout: 2.0)

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

        let sseDisabledExpectation = expectation(description: "SSE disabled")
        sseDisabledExpectation.expectedFulfillmentCount = 1
        sseDisabledExpectation.assertForOverFulfill = true

        inAppMessageManagerMock.dispatchClosure = { action, _ in
            if case .setSseEnabled(enabled: false) = action {
                sseDisabledExpectation.fulfill()
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

        // Emit maxRetriesReached decision (with generation 1)
        retryContinuation.yield((.maxRetriesReached, 1))

        await fulfillment(of: [sseDisabledExpectation], timeout: 1.0)

        // Give any duplicate dispatch time to appear (it won't if correct)
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms observation window

        // Clean up
        sseContinuation.finish()
        retryContinuation.finish()

        // Assert: Check that SSE was disabled exactly once
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

        let sseDisabledExpectation = expectation(description: "SSE disabled")
        sseDisabledExpectation.expectedFulfillmentCount = 1
        sseDisabledExpectation.assertForOverFulfill = true

        inAppMessageManagerMock.dispatchClosure = { action, _ in
            if case .setSseEnabled(enabled: false) = action {
                sseDisabledExpectation.fulfill()
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

        retryContinuation.yield((.retryNotPossible, 1))

        await fulfillment(of: [sseDisabledExpectation], timeout: 1.0)

        // Give any duplicate dispatch time to appear (it won't if correct)
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms observation window

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

/// Thread-safe counter for tracking mock invocations across async contexts.
private final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    /// Increments and returns the new count.
    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
