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

    /// Long enough that a loaded runner never trips it. A passing test returns as soon as the call it
    /// waits for happens, so this only bounds how long a broken test takes to fail.
    private let signalTimeout: TimeInterval = 10

    /// An expectation a mock hook fulfills when the call the test is waiting for happens.
    private func signal(_ description: String) -> XCTestExpectation {
        let signal = expectation(description: description)
        signal.assertForOverFulfill = false
        return signal
    }

    /// Makes `connect` return `stream` and runs `onConnect` on every call.
    private func stubConnect(returning stream: AsyncStream<SseEvent>, onConnect: @escaping () -> Void = {}) {
        sseServiceMock.connectClosure = { _, _ in
            onConnect()
            return stream
        }
    }

    /// Makes the in-app manager record dispatches like the real one and runs `onDispatch` on every call.
    private func stubDispatch(onDispatch: @escaping (InAppMessageAction) -> Void = { _ in }) {
        inAppMessageManagerMock.dispatchClosure = { action, _ in
            onDispatch(action)
            return Task {}
        }
    }

    private func isSseDisabled(_ action: InAppMessageAction) -> Bool {
        if case .setSseEnabled(enabled: false) = action { return true }
        return false
    }

    private var sseDisabledDispatchCount: Int {
        inAppMessageManagerMock.dispatchReceivedInvocations.filter { isSseDisabled($0.action) }.count
    }

    // MARK: - Start Connection Tests

    func test_startConnection_expectSseServiceConnectCalled() async {
        // Setup: SSE service returns a stream that completes immediately
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        let connected = signal("the SSE service to connect")
        stubConnect(returning: stream) { connected.fulfill() }
        continuation.finish()

        // Action
        await sut.startConnection()

        await fulfillment(of: [connected], timeout: signalTimeout)

        // Assert
        XCTAssertTrue(sseServiceMock.connectCalled)
        XCTAssertEqual(sseServiceMock.connectCallsCount, 1)
    }

    func test_startConnection_givenAlreadyConnecting_expectNoSecondConnect() async {
        // Setup: SSE service returns a stream that doesn't complete (simulating ongoing connection)
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        let firstConnect = signal("the first SSE connection")
        stubConnect(returning: stream) { firstConnect.fulfill() }

        // Action: Start connection twice
        await sut.startConnection()

        await fulfillment(of: [firstConnect], timeout: signalTimeout)

        await sut.startConnection()

        // Assert: A second start that took the early return never reaches `setActiveGeneration`,
        // which every real start calls before it spawns a connection task.
        XCTAssertEqual(retryHelperMock.setActiveGenerationCallsCount, 1)
        XCTAssertEqual(sseServiceMock.connectCallsCount, 1)
    }

    func test_startConnection_expectHeartbeatCallbackSet() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream
        continuation.finish()

        // Action: the callback is set inside `startConnection()`, so it is set once that returns.
        await sut.startConnection()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.setCallbackCalled)
    }

    // MARK: - Stop Connection Tests

    func test_stopConnection_expectSseServiceDisconnectCalled() async {
        // Setup: Start a connection first
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        let connected = signal("the SSE service to connect")
        stubConnect(returning: stream) { connected.fulfill() }

        await sut.startConnection()
        await fulfillment(of: [connected], timeout: signalTimeout)

        // Action
        await sut.stopConnection()

        // Assert
        XCTAssertTrue(sseServiceMock.disconnectCalled)
    }

    func test_stopConnection_expectRetryStateReset() async {
        // Setup
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        let connected = signal("the SSE service to connect")
        stubConnect(returning: stream) { connected.fulfill() }

        await sut.startConnection()
        await fulfillment(of: [connected], timeout: signalTimeout)

        // Action
        await sut.stopConnection()

        // Assert
        XCTAssertTrue(retryHelperMock.resetRetryStateCalled)
    }

    func test_stopConnection_expectHeartbeatTimerReset() async {
        // Setup
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        let connected = signal("the SSE service to connect")
        stubConnect(returning: stream) { connected.fulfill() }

        await sut.startConnection()
        await fulfillment(of: [connected], timeout: signalTimeout)

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

        let timerStarted = signal("the heartbeat timer to start")
        heartbeatTimerMock.startTimerClosure = { _, _ in timerStarted.fulfill() }

        // Action
        await sut.startConnection()

        // Send connectionOpen event
        continuation.yield(.connectionOpen)
        await fulfillment(of: [timerStarted], timeout: signalTimeout)

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
        let streamEnded = signal("the event stream to finish")
        heartbeatTimerMock.resetClosure = { _ in streamEnded.fulfill() }

        await sut.startConnection()
        continuation.yield(.connectionOpen)
        continuation.yield(.serverEvent(ServerEvent(id: nil, type: "connected", data: "")))
        continuation.finish()
        await fulfillment(of: [streamEnded], timeout: signalTimeout)

        XCTAssertEqual(counter.value, 1)
    }

    func test_transportOpenOnly_expectNoConnectionConfirmed() async {
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let counter = ConfirmationCounter()
        await sut.setOnConnectionConfirmed { counter.increment() }
        let streamEnded = signal("the event stream to finish")
        heartbeatTimerMock.resetClosure = { _ in streamEnded.fulfill() }

        await sut.startConnection()
        continuation.yield(.connectionOpen)
        continuation.finish()
        await fulfillment(of: [streamEnded], timeout: signalTimeout)

        // Transport open alone is not confirmation: nothing should be backfilled yet.
        XCTAssertEqual(counter.value, 0)
    }

    func test_connectionOpen_expectRetryStateReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let retryStateReset = signal("the retry state to reset")
        retryHelperMock.resetRetryStateClosure = { _ in retryStateReset.fulfill() }

        // Action
        await sut.startConnection()
        continuation.yield(.connectionOpen)
        await fulfillment(of: [retryStateReset], timeout: signalTimeout)
        continuation.finish()

        // Assert
        XCTAssertTrue(retryHelperMock.resetRetryStateCalled)
    }

    func test_connectionFailed_givenRetryableError_expectRetryScheduled() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let retryScheduled = signal("the retry to be scheduled")
        retryHelperMock.scheduleRetryClosure = { _, _ in retryScheduled.fulfill() }

        // Action
        await sut.startConnection()

        let error = SseError.networkError(message: "Connection failed", underlyingError: nil)
        continuation.yield(.connectionFailed(error))
        await fulfillment(of: [retryScheduled], timeout: signalTimeout)
        continuation.finish()

        // Assert
        XCTAssertTrue(retryHelperMock.scheduleRetryCalled)
        XCTAssertEqual(retryHelperMock.scheduleRetryReceivedArguments?.error, error)
    }

    func test_connectionFailed_expectHeartbeatTimerReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let timerReset = signal("the heartbeat timer to reset")
        heartbeatTimerMock.resetClosure = { _ in timerReset.fulfill() }

        // Action
        await sut.startConnection()
        continuation.yield(.connectionFailed(.networkError(message: "Error", underlyingError: nil)))
        await fulfillment(of: [timerReset], timeout: signalTimeout)
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.resetCalled)
    }

    func test_connectionClosed_expectHeartbeatTimerReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let timerReset = signal("the heartbeat timer to reset")
        heartbeatTimerMock.resetClosure = { _ in timerReset.fulfill() }

        // Action
        await sut.startConnection()
        continuation.yield(.connectionClosed)
        await fulfillment(of: [timerReset], timeout: signalTimeout)
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.resetCalled)
    }

    // MARK: - Server Event Tests

    func test_serverEvent_givenConnectedEvent_expectHeartbeatTimerStarted() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let timerStarted = signal("the heartbeat timer to start")
        heartbeatTimerMock.startTimerClosure = { _, _ in timerStarted.fulfill() }

        // Action
        await sut.startConnection()

        let serverEvent = ServerEvent(id: nil, type: "connected", data: "{}")
        continuation.yield(.serverEvent(serverEvent))
        await fulfillment(of: [timerStarted], timeout: signalTimeout)
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.startTimerCalled)
    }

    func test_serverEvent_givenHeartbeatEvent_expectHeartbeatTimerRestarted() async {
        // Setup
        let (stream, streamContinuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // Set the closure before starting the connection to avoid a race condition where
        // startTimerCallsCount reaches 2 before the closure is assigned.
        let heartbeatTimerStartedTwice = XCTestExpectation(description: "Heartbeat timer started at least twice")
        heartbeatTimerMock.startTimerClosure = { [weak heartbeatTimerMock] _, _ in
            guard let mock = heartbeatTimerMock, mock.startTimerCallsCount == 2 else { return }
            heartbeatTimerStartedTwice.fulfill()
        }

        // Action
        await sut.startConnection()
        streamContinuation.yield(.connectionOpen)
        streamContinuation.yield(.serverEvent(ServerEvent(id: nil, type: "heartbeat", data: "{\"heartbeat\": 30}")))
        streamContinuation.finish()

        await fulfillment(of: [heartbeatTimerStartedTwice], timeout: signalTimeout)

        // Assert: Timer started for connection open and again for heartbeat
        XCTAssertGreaterThanOrEqual(heartbeatTimerMock.startTimerCallsCount, 2)
    }

    func test_serverEvent_givenMessagesEvent_expectMessagesDispatched() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        stubDispatch()
        let streamEnded = signal("the event stream to finish")
        heartbeatTimerMock.resetClosure = { _ in streamEnded.fulfill() }

        // Action
        await sut.startConnection()

        // Create a valid messages event with proper JSON
        let messagesJson = """
        [{"queueId": "q1", "priority": 1, "messageId": "m1"}]
        """
        let messagesEvent = ServerEvent(id: nil, type: "messages", data: messagesJson)
        continuation.yield(.serverEvent(messagesEvent))
        continuation.finish()
        await fulfillment(of: [streamEnded], timeout: signalTimeout)

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
        let sentinelConnect = signal("the connection started by the sentinel retry decision")
        stubConnect(returning: sseStream) { [self] in
            if sseServiceMock.connectCallsCount == 2 { sentinelConnect.fulfill() }
        }

        let sseDisabled = signal("SSE to be disabled")
        stubDispatch { [self] action in
            if isSseDisabled(action) { sseDisabled.fulfill() }
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
        await fulfillment(of: [sseDisabled], timeout: signalTimeout)

        // Decisions are handled one at a time, in order. Once this sentinel decision has started a new
        // connection, a duplicate dispatch from the decision above would already have happened.
        // This relies on the manager still acting on retry decisions after a full failure; if that
        // changes, this wait times out on the sentinel connect instead of failing on the count.
        retryContinuation.yield((.retryNow(attemptCount: 1), 1))
        await fulfillment(of: [sentinelConnect], timeout: signalTimeout)

        // Clean up
        sseContinuation.finish()
        retryContinuation.finish()

        // Assert: Check that SSE was disabled (fallback to polling)
        XCTAssertEqual(sseDisabledDispatchCount, 1)
    }

    func test_retryDecision_givenRetryNotPossible_expectFallbackToPolling() async {
        // Setup
        let (retryStream, retryContinuation) = AsyncStreamBackport.makeStream(of: (RetryDecision, UInt64).self)
        retryHelperMock.createNewRetryStreamReturnValue = retryStream

        let (sseStream, sseContinuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        let sentinelConnect = signal("the connection started by the sentinel retry decision")
        stubConnect(returning: sseStream) { [self] in
            if sseServiceMock.connectCallsCount == 2 { sentinelConnect.fulfill() }
        }

        let sseDisabled = signal("SSE to be disabled")
        stubDispatch { [self] action in
            if isSseDisabled(action) { sseDisabled.fulfill() }
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
        await fulfillment(of: [sseDisabled], timeout: signalTimeout)

        // Decisions are handled one at a time, in order. Once this sentinel decision has started a new
        // connection, a duplicate dispatch from the decision above would already have happened.
        // This relies on the manager still acting on retry decisions after a full failure; if that
        // changes, this wait times out on the sentinel connect instead of failing on the count.
        retryContinuation.yield((.retryNow(attemptCount: 1), 1))
        await fulfillment(of: [sentinelConnect], timeout: signalTimeout)

        sseContinuation.finish()
        retryContinuation.finish()

        // Assert
        XCTAssertEqual(sseDisabledDispatchCount, 1)
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
