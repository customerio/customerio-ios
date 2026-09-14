@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioMessagingInAppMocks
@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

/// Tests for `SseConnectionManager` actor.
/// Tests use XCTestExpectation for reliable async synchronization.
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

    /// Keeps observing a negative or exact-count assertion long enough for a wrongly spawned task
    /// or duplicate callback to become visible, while failing immediately if the invariant breaks.
    private func assertRemainsTrue(
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) async {
        for _ in 0 ..< 20 {
            guard condition() else {
                XCTFail(message, file: file, line: line)
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 5000000)
        }
    }

    // MARK: - Start Connection Tests

    func test_startConnection_expectSseServiceConnectCalled() async {
        let (stream, streamContinuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        streamContinuation.finish()

        let exp = expectation(description: "connect called")
        sseServiceMock.connectClosure = { [stream] _, _ in
            exp.fulfill()
            return stream
        }

        await sut.startConnection()
        await fulfillment(of: [exp], timeout: 10.0)

        XCTAssertTrue(sseServiceMock.connectCalled)
        XCTAssertEqual(sseServiceMock.connectCallsCount, 1)
    }

    func test_startConnection_givenAlreadyConnecting_expectNoSecondConnect() async {
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        let exp = expectation(description: "first connect")
        sseServiceMock.connectClosure = { [stream] _, _ in
            exp.fulfill()
            return stream
        }

        await sut.startConnection()
        await fulfillment(of: [exp], timeout: 10.0)

        await sut.startConnection()

        await assertRemainsTrue("Starting an active connection scheduled a second SSE connection") {
            sseServiceMock.connectCallsCount == 1
        }
        XCTAssertEqual(sseServiceMock.connectCallsCount, 1)
    }

    func test_startConnection_expectHeartbeatCallbackSet() async {
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream
        continuation.finish()

        let exp = expectation(description: "callback set")
        heartbeatTimerMock.setCallbackClosure = { _ in
            exp.fulfill()
        }

        await sut.startConnection()
        await fulfillment(of: [exp], timeout: 10.0)

        XCTAssertTrue(heartbeatTimerMock.setCallbackCalled)
    }

    // MARK: - Stop Connection Tests

    func test_stopConnection_expectSseServiceDisconnectCalled() async {
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        let connectedExp = expectation(description: "connected")
        sseServiceMock.connectClosure = { [stream] _, _ in
            connectedExp.fulfill()
            return stream
        }

        await sut.startConnection()
        await fulfillment(of: [connectedExp], timeout: 10.0)

        await sut.stopConnection()

        XCTAssertTrue(sseServiceMock.disconnectCalled)
    }

    func test_stopConnection_expectRetryStateReset() async {
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        let connectedExp = expectation(description: "connected")
        sseServiceMock.connectClosure = { [stream] _, _ in
            connectedExp.fulfill()
            return stream
        }

        await sut.startConnection()
        await fulfillment(of: [connectedExp], timeout: 10.0)

        await sut.stopConnection()

        XCTAssertTrue(retryHelperMock.resetRetryStateCalled)
    }

    func test_stopConnection_expectHeartbeatTimerReset() async {
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        let connectedExp = expectation(description: "connected")
        sseServiceMock.connectClosure = { [stream] _, _ in
            connectedExp.fulfill()
            return stream
        }

        await sut.startConnection()
        await fulfillment(of: [connectedExp], timeout: 10.0)

        await sut.stopConnection()

        XCTAssertTrue(heartbeatTimerMock.resetCalled)
    }

    // MARK: - Connection Events Tests

    func test_connectionOpen_expectHeartbeatTimerStarted() async {
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let timerExp = expectation(description: "timer started")
        heartbeatTimerMock.startTimerClosure = { _, _ in
            timerExp.fulfill()
        }

        await sut.startConnection()
        continuation.yield(.connectionOpen)

        await fulfillment(of: [timerExp], timeout: 10.0)
        continuation.finish()

        XCTAssertTrue(heartbeatTimerMock.startTimerCalled)
    }

    func test_openThenConnected_expectConnectionConfirmedExactlyOnce() async {
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let counter = ConfirmationCounter()
        await sut.setOnConnectionConfirmed { counter.increment() }

        let streamFinishedExp = expectation(description: "stream finished")
        var fulfilled = false
        heartbeatTimerMock.resetClosure = { _ in
            guard !fulfilled else { return }
            fulfilled = true
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
        var fulfilled = false
        heartbeatTimerMock.resetClosure = { _ in
            guard !fulfilled else { return }
            fulfilled = true
            streamFinishedExp.fulfill()
        }

        await sut.startConnection()
        continuation.yield(.connectionOpen)
        continuation.finish()

        await fulfillment(of: [streamFinishedExp], timeout: 10.0)

        XCTAssertEqual(counter.value, 0)
    }

    func test_connectionOpen_expectRetryStateReset() async {
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let exp = expectation(description: "retry reset")
        retryHelperMock.resetRetryStateClosure = { _ in
            exp.fulfill()
        }

        await sut.startConnection()
        continuation.yield(.connectionOpen)

        await fulfillment(of: [exp], timeout: 10.0)
        continuation.finish()

        XCTAssertTrue(retryHelperMock.resetRetryStateCalled)
    }

    func test_connectionFailed_givenRetryableError_expectRetryScheduled() async {
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let error = SseError.networkError(message: "Connection failed", underlyingError: nil)

        let exp = expectation(description: "retry scheduled")
        retryHelperMock.scheduleRetryClosure = { _, _ in
            exp.fulfill()
        }

        await sut.startConnection()
        continuation.yield(.connectionFailed(error))

        await fulfillment(of: [exp], timeout: 10.0)
        continuation.finish()

        XCTAssertTrue(retryHelperMock.scheduleRetryCalled)
        XCTAssertEqual(retryHelperMock.scheduleRetryReceivedArguments?.error, error)
    }

    func test_connectionFailed_expectHeartbeatTimerReset() async {
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let exp = expectation(description: "timer reset")
        var fulfilled = false
        heartbeatTimerMock.resetClosure = { _ in
            guard !fulfilled else { return }
            fulfilled = true
            exp.fulfill()
        }

        await sut.startConnection()
        continuation.yield(.connectionFailed(.networkError(message: "Error", underlyingError: nil)))

        await fulfillment(of: [exp], timeout: 10.0)
        continuation.finish()

        XCTAssertTrue(heartbeatTimerMock.resetCalled)
    }

    func test_connectionClosed_expectHeartbeatTimerReset() async {
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let exp = expectation(description: "timer reset")
        var fulfilled = false
        heartbeatTimerMock.resetClosure = { _ in
            guard !fulfilled else { return }
            fulfilled = true
            exp.fulfill()
        }

        await sut.startConnection()
        continuation.yield(.connectionClosed)

        await fulfillment(of: [exp], timeout: 10.0)
        continuation.finish()

        XCTAssertTrue(heartbeatTimerMock.resetCalled)
    }

    // MARK: - Server Event Tests

    func test_serverEvent_givenConnectedEvent_expectHeartbeatTimerStarted() async {
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let exp = expectation(description: "timer started")
        heartbeatTimerMock.startTimerClosure = { _, _ in
            exp.fulfill()
        }

        await sut.startConnection()
        continuation.yield(.serverEvent(ServerEvent(id: nil, type: "connected", data: "{}")))

        await fulfillment(of: [exp], timeout: 10.0)
        continuation.finish()

        XCTAssertTrue(heartbeatTimerMock.startTimerCalled)
    }

    func test_serverEvent_givenHeartbeatEvent_expectHeartbeatTimerRestarted() async {
        // Setup: resume when startTimer is called the second time (March pattern)
        let (stream, streamContinuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let secondTimerExp = expectation(description: "timer started second time")
        heartbeatTimerMock.startTimerClosure = { [weak heartbeatTimerMock] _, _ in
            guard let mock = heartbeatTimerMock, mock.startTimerCallsCount == 2 else { return }
            secondTimerExp.fulfill()
        }

        await sut.startConnection()
        streamContinuation.yield(.connectionOpen)
        streamContinuation.yield(.serverEvent(ServerEvent(id: nil, type: "heartbeat", data: "{\"heartbeat\": 30}")))
        streamContinuation.finish()

        await fulfillment(of: [secondTimerExp], timeout: 10.0)

        XCTAssertGreaterThanOrEqual(heartbeatTimerMock.startTimerCallsCount, 2)
    }

    func test_serverEvent_givenMessagesEvent_expectMessagesDispatched() async {
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let exp = expectation(description: "messages dispatched")
        inAppMessageManagerMock.dispatchClosure = { action, _ in
            if case .processMessageQueue = action {
                exp.fulfill()
            }
            return Task {}
        }

        await sut.startConnection()
        let messagesJson = """
        [{"queueId": "q1", "priority": 1, "messageId": "m1"}]
        """
        continuation.yield(.serverEvent(ServerEvent(id: nil, type: "messages", data: messagesJson)))

        await fulfillment(of: [exp], timeout: 10.0)
        continuation.finish()

        let processActions = inAppMessageManagerMock.dispatchReceivedInvocations.filter {
            if case .processMessageQueue = $0.action { return true }
            return false
        }
        XCTAssertEqual(processActions.count, 1)
    }

    // MARK: - Retry Decision Tests

    func test_retryDecision_givenMaxRetriesReached_expectFallbackToPolling() async {
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

        let exp = expectation(description: "SSE disabled")
        var fulfilled = false
        inAppMessageManagerMock.dispatchClosure = { action, _ in
            if case .setSseEnabled(enabled: false) = action {
                guard !fulfilled else { return Task {} }
                fulfilled = true
                exp.fulfill()
            }
            return Task {}
        }

        await sut.startConnection()
        retryContinuation.yield((.maxRetriesReached, 1))

        await fulfillment(of: [exp], timeout: 10.0)

        try? await Task.sleep(nanoseconds: 50_000_000)

        sseContinuation.finish()
        retryContinuation.finish()

        let sseDisabledActions = inAppMessageManagerMock.dispatchReceivedInvocations.filter {
            if case .setSseEnabled(enabled: false) = $0.action { return true }
            return false
        }
        XCTAssertEqual(sseDisabledActions.count, 1)
    }

    func test_retryDecision_givenRetryNotPossible_expectFallbackToPolling() async {
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

        let exp = expectation(description: "SSE disabled")
        var fulfilled = false
        inAppMessageManagerMock.dispatchClosure = { action, _ in
            if case .setSseEnabled(enabled: false) = action {
                guard !fulfilled else { return Task {} }
                fulfilled = true
                exp.fulfill()
            }
            return Task {}
        }

        await sut.startConnection()
        retryContinuation.yield((.retryNotPossible, 1))

        await fulfillment(of: [exp], timeout: 10.0)

        try? await Task.sleep(nanoseconds: 50_000_000)

        sseContinuation.finish()
        retryContinuation.finish()

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
