@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioMessagingInAppMocks
@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

/// Tests for `SseConnectionManager` actor.
/// All async tests use XCTestExpectation with await fulfillment(of:) for reliable timing.
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

    // MARK: - Start Connection Tests

    func test_startConnection_expectSseServiceConnectCalled() async {
        // Setup
        let (stream, streamContinuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        streamContinuation.finish()

        let connectExp = expectation(description: "connect called")
        sseServiceMock.connectClosure = { [stream] _, _ in
            connectExp.fulfill()
            return stream
        }

        // Action
        await sut.startConnection()
        await fulfillment(of: [connectExp], timeout: 10.0)

        // Assert
        XCTAssertTrue(sseServiceMock.connectCalled)
        XCTAssertEqual(sseServiceMock.connectCallsCount, 1)
    }

    func test_startConnection_givenAlreadyConnecting_expectNoSecondConnect() async {
        // Setup
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        let connectExp = expectation(description: "connect called")
        sseServiceMock.connectClosure = { [stream] _, _ in
            connectExp.fulfill()
            return stream
        }

        // Action: Start connection twice
        await sut.startConnection()
        await fulfillment(of: [connectExp], timeout: 10.0)

        await sut.startConnection()

        // Brief yield to let any wrongly spawned task become visible
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Assert: only one connect call
        XCTAssertEqual(sseServiceMock.connectCallsCount, 1)
    }

    func test_startConnection_expectHeartbeatCallbackSet() async {
        // Setup
        let (stream, streamContinuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        streamContinuation.finish()
        sseServiceMock.connectReturnValue = stream

        let callbackSetExp = expectation(description: "setCallback called")
        heartbeatTimerMock.setCallbackClosure = { _ in
            callbackSetExp.fulfill()
        }

        // Action
        await sut.startConnection()
        await fulfillment(of: [callbackSetExp], timeout: 10.0)

        // Assert
        XCTAssertTrue(heartbeatTimerMock.setCallbackCalled)
    }

    // MARK: - Stop Connection Tests

    func test_stopConnection_expectSseServiceDisconnectCalled() async {
        // Setup
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        let connectExp = expectation(description: "connect called")
        sseServiceMock.connectClosure = { [stream] _, _ in
            connectExp.fulfill()
            return stream
        }

        await sut.startConnection()
        await fulfillment(of: [connectExp], timeout: 10.0)

        // Action
        await sut.stopConnection()

        // Assert
        XCTAssertTrue(sseServiceMock.disconnectCalled)
    }

    func test_stopConnection_expectRetryStateReset() async {
        // Setup
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        let connectExp = expectation(description: "connect called")
        sseServiceMock.connectClosure = { [stream] _, _ in
            connectExp.fulfill()
            return stream
        }

        await sut.startConnection()
        await fulfillment(of: [connectExp], timeout: 10.0)

        // Action
        await sut.stopConnection()

        // Assert
        XCTAssertTrue(retryHelperMock.resetRetryStateCalled)
    }

    func test_stopConnection_expectHeartbeatTimerReset() async {
        // Setup
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        let connectExp = expectation(description: "connect called")
        sseServiceMock.connectClosure = { [stream] _, _ in
            connectExp.fulfill()
            return stream
        }

        await sut.startConnection()
        await fulfillment(of: [connectExp], timeout: 10.0)

        // Action
        await sut.stopConnection()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.resetCalled)
    }

    // MARK: - Connection Events Tests

    func test_connectionOpen_expectHeartbeatTimerStarted() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let timerStartedExp = expectation(description: "timer started")
        heartbeatTimerMock.startTimerClosure = { _, _ in
            timerStartedExp.fulfill()
        }

        // Action
        await sut.startConnection()
        continuation.yield(.connectionOpen)

        await fulfillment(of: [timerStartedExp], timeout: 10.0)
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.startTimerCalled)
    }

    func test_openThenConnected_expectConnectionConfirmedExactlyOnce() async {
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let counter = ConfirmationCounter()
        await sut.setOnConnectionConfirmed { counter.increment() }

        let streamFinishedExp = expectation(description: "stream finished")
        var streamFinishedFulfilled = false
        heartbeatTimerMock.resetClosure = { _ in
            guard !streamFinishedFulfilled else { return }
            streamFinishedFulfilled = true
            streamFinishedExp.fulfill()
        }

        await sut.startConnection()
        continuation.yield(.connectionOpen)
        continuation.yield(.serverEvent(ServerEvent(id: nil, type: "connected", data: "")))
        continuation.finish()

        await fulfillment(of: [streamFinishedExp], timeout: 10.0)

        XCTAssertEqual(counter.value, 1)
    }

    func test_transportOpenOnly_expectNoConnectionConfirmed() async {
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let counter = ConfirmationCounter()
        await sut.setOnConnectionConfirmed { counter.increment() }

        let streamFinishedExp = expectation(description: "stream finished")
        var streamFinishedFulfilled = false
        heartbeatTimerMock.resetClosure = { _ in
            guard !streamFinishedFulfilled else { return }
            streamFinishedFulfilled = true
            streamFinishedExp.fulfill()
        }

        await sut.startConnection()
        continuation.yield(.connectionOpen)
        continuation.finish()

        await fulfillment(of: [streamFinishedExp], timeout: 10.0)

        XCTAssertEqual(counter.value, 0)
    }

    func test_connectionOpen_expectRetryStateReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let retryResetExp = expectation(description: "retry state reset")
        retryHelperMock.resetRetryStateClosure = { _ in
            retryResetExp.fulfill()
        }

        // Action
        await sut.startConnection()
        continuation.yield(.connectionOpen)

        await fulfillment(of: [retryResetExp], timeout: 10.0)
        continuation.finish()

        // Assert
        XCTAssertTrue(retryHelperMock.resetRetryStateCalled)
    }

    func test_connectionFailed_givenRetryableError_expectRetryScheduled() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let error = SseError.networkError(message: "Connection failed", underlyingError: nil)

        let retryScheduledExp = expectation(description: "retry scheduled")
        retryHelperMock.scheduleRetryClosure = { _, _ in
            retryScheduledExp.fulfill()
        }

        // Action
        await sut.startConnection()
        continuation.yield(.connectionFailed(error))

        await fulfillment(of: [retryScheduledExp], timeout: 10.0)
        continuation.finish()

        // Assert
        XCTAssertTrue(retryHelperMock.scheduleRetryCalled)
        XCTAssertEqual(retryHelperMock.scheduleRetryReceivedArguments?.error, error)
    }

    func test_connectionFailed_expectHeartbeatTimerReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let timerResetExp = expectation(description: "timer reset")
        var timerResetFulfilled = false
        heartbeatTimerMock.resetClosure = { _ in
            guard !timerResetFulfilled else { return }
            timerResetFulfilled = true
            timerResetExp.fulfill()
        }

        // Action
        await sut.startConnection()
        continuation.yield(.connectionFailed(.networkError(message: "Error", underlyingError: nil)))

        await fulfillment(of: [timerResetExp], timeout: 10.0)
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.resetCalled)
    }

    func test_connectionClosed_expectHeartbeatTimerReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let timerResetExp = expectation(description: "timer reset")
        var timerResetFulfilled = false
        heartbeatTimerMock.resetClosure = { _ in
            guard !timerResetFulfilled else { return }
            timerResetFulfilled = true
            timerResetExp.fulfill()
        }

        // Action
        await sut.startConnection()
        continuation.yield(.connectionClosed)

        await fulfillment(of: [timerResetExp], timeout: 10.0)
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.resetCalled)
    }

    // MARK: - Server Event Tests

    func test_serverEvent_givenConnectedEvent_expectHeartbeatTimerStarted() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let timerStartedExp = expectation(description: "timer started")
        heartbeatTimerMock.startTimerClosure = { _, _ in
            timerStartedExp.fulfill()
        }

        // Action
        await sut.startConnection()
        continuation.yield(.serverEvent(ServerEvent(id: nil, type: "connected", data: "{}")))

        await fulfillment(of: [timerStartedExp], timeout: 10.0)
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.startTimerCalled)
    }

    func test_serverEvent_givenHeartbeatEvent_expectHeartbeatTimerRestarted() async {
        // Setup: resume when startTimer is called the second time
        let (stream, streamContinuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let secondStartTimerExp = expectation(description: "timer started second time")
        heartbeatTimerMock.startTimerClosure = { [weak heartbeatTimerMock] _, _ in
            guard let mock = heartbeatTimerMock, mock.startTimerCallsCount == 2 else { return }
            secondStartTimerExp.fulfill()
        }

        // Action
        await sut.startConnection()
        streamContinuation.yield(.connectionOpen)
        streamContinuation.yield(.serverEvent(ServerEvent(id: nil, type: "heartbeat", data: "{\"heartbeat\": 30}")))
        streamContinuation.finish()

        await fulfillment(of: [secondStartTimerExp], timeout: 10.0)

        // Assert
        XCTAssertGreaterThanOrEqual(heartbeatTimerMock.startTimerCallsCount, 2)
    }

    func test_serverEvent_givenMessagesEvent_expectMessagesDispatched() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let dispatchedExp = expectation(description: "messages dispatched")
        inAppMessageManagerMock.dispatchClosure = { action, _ in
            if case .processMessageQueue = action {
                dispatchedExp.fulfill()
            }
            return Task {}
        }

        // Action
        await sut.startConnection()
        let messagesJson = """
        [{"queueId": "q1", "priority": 1, "messageId": "m1"}]
        """
        continuation.yield(.serverEvent(ServerEvent(id: nil, type: "messages", data: messagesJson)))

        await fulfillment(of: [dispatchedExp], timeout: 10.0)
        continuation.finish()

        // Assert
        let processActions = inAppMessageManagerMock.dispatchReceivedInvocations.filter {
            if case .processMessageQueue = $0.action { return true }
            return false
        }
        XCTAssertEqual(processActions.count, 1)
    }

    // MARK: - Retry Decision Tests

    func test_retryDecision_givenMaxRetriesReached_expectFallbackToPolling() async {
        // Setup
        let (retryStream, retryContinuation) = AsyncStreamBackport.makeStream(of: (RetryDecision, UInt64).self)
        retryHelperMock.createNewRetryStreamReturnValue = retryStream

        let (sseStream, sseContinuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = sseStream

        sut = SseConnectionManager(
            logger: loggerMock,
            inAppMessageManager: inAppMessageManagerMock,
            sseService: sseServiceMock,
            retryHelper: retryHelperMock,
            heartbeatTimer: heartbeatTimerMock
        )

        let sseDisabledExp = expectation(description: "SSE disabled")
        var sseDisabledFulfilled = false
        inAppMessageManagerMock.dispatchClosure = { action, _ in
            if case .setSseEnabled(enabled: false) = action {
                guard !sseDisabledFulfilled else { return Task {} }
                sseDisabledFulfilled = true
                sseDisabledExp.fulfill()
            }
            return Task {}
        }

        // Action
        await sut.startConnection()
        retryContinuation.yield((.maxRetriesReached, 1))

        await fulfillment(of: [sseDisabledExp], timeout: 10.0)

        // Brief window to catch duplicates
        try? await Task.sleep(nanoseconds: 50_000_000)

        sseContinuation.finish()
        retryContinuation.finish()

        // Assert
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

        sut = SseConnectionManager(
            logger: loggerMock,
            inAppMessageManager: inAppMessageManagerMock,
            sseService: sseServiceMock,
            retryHelper: retryHelperMock,
            heartbeatTimer: heartbeatTimerMock
        )

        let sseDisabledExp = expectation(description: "SSE disabled")
        var sseDisabledFulfilled = false
        inAppMessageManagerMock.dispatchClosure = { action, _ in
            if case .setSseEnabled(enabled: false) = action {
                guard !sseDisabledFulfilled else { return Task {} }
                sseDisabledFulfilled = true
                sseDisabledExp.fulfill()
            }
            return Task {}
        }

        // Action
        await sut.startConnection()
        retryContinuation.yield((.retryNotPossible, 1))

        await fulfillment(of: [sseDisabledExp], timeout: 10.0)

        try? await Task.sleep(nanoseconds: 50_000_000)

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

/// Counts hook invocations from a `@Sendable` closure.
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
