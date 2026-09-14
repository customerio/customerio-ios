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

    /// Awaits until the predicate returns true, using XCTestExpectation for proper async handling.
    /// Unlike a poll loop with Task.sleep, this cooperates with the XCTest runtime.
    private func awaitCondition(
        _ description: String,
        timeout: TimeInterval = 3.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        predicate: @escaping () -> Bool
    ) async {
        let exp = expectation(description: description)
        exp.expectedFulfillmentCount = 1

        // Use a polling task that yields frequently
        let pollingTask = Task {
            while !Task.isCancelled {
                if predicate() {
                    exp.fulfill()
                    return
                }
                await Task.yield()
            }
        }

        await fulfillment(of: [exp], timeout: timeout)
        pollingTask.cancel()
    }

    /// Keeps observing a negative or exact-count assertion long enough for a wrongly spawned task
    /// or duplicate callback to become visible, while failing immediately if the invariant breaks.
    private func assertRemainsTrue(
        _ message: String,
        observationTime: TimeInterval = 0.1,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping () -> Bool
    ) async {
        let exp = expectation(description: "Observation window")
        exp.isInverted = true // We expect it NOT to be fulfilled

        let checkTask = Task {
            while !Task.isCancelled {
                guard condition() else {
                    exp.fulfill() // Invariant broken!
                    return
                }
                await Task.yield()
            }
        }

        // Wait for the observation window - if exp is fulfilled, test fails
        await fulfillment(of: [exp], timeout: observationTime)
        checkTask.cancel()

        // Final check
        XCTAssertTrue(condition(), message, file: file, line: line)
    }

    // MARK: - Start Connection Tests

    func test_startConnection_expectSseServiceConnectCalled() async {
        // Setup: SSE service returns a stream that completes immediately
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream
        continuation.finish()

        // Action
        await sut.startConnection()

        await awaitCondition("the SSE service to connect") { self.sseServiceMock.connectCalled }

        // Assert
        XCTAssertTrue(sseServiceMock.connectCalled)
        XCTAssertEqual(sseServiceMock.connectCallsCount, 1)
    }

    func test_startConnection_givenAlreadyConnecting_expectNoSecondConnect() async {
        // Setup: SSE service returns a stream that doesn't complete (simulating ongoing connection)
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // Action: Start connection twice
        await sut.startConnection()

        await awaitCondition("the first SSE connection") { self.sseServiceMock.connectCallsCount == 1 }

        await sut.startConnection()

        // Assert: Give any wrongly spawned connection task a bounded window to become visible.
        await assertRemainsTrue("Starting an active connection scheduled a second SSE connection") {
            self.sseServiceMock.connectCallsCount == 1
        }
        XCTAssertEqual(sseServiceMock.connectCallsCount, 1)
    }

    func test_startConnection_expectHeartbeatCallbackSet() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream
        continuation.finish()

        // Action
        await sut.startConnection()
        await awaitCondition("the heartbeat callback") { self.heartbeatTimerMock.setCallbackCalled }

        // Assert
        XCTAssertTrue(heartbeatTimerMock.setCallbackCalled)
    }

    // MARK: - Stop Connection Tests

    func test_stopConnection_expectSseServiceDisconnectCalled() async {
        // Setup: Start a connection first
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        await sut.startConnection()
        await awaitCondition("the SSE service to connect") { self.sseServiceMock.connectCalled }

        // Action
        await sut.stopConnection()

        // Assert
        XCTAssertTrue(sseServiceMock.disconnectCalled)
    }

    func test_stopConnection_expectRetryStateReset() async {
        // Setup
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        await sut.startConnection()
        await awaitCondition("the SSE service to connect") { self.sseServiceMock.connectCalled }

        // Action
        await sut.stopConnection()

        // Assert
        XCTAssertTrue(retryHelperMock.resetRetryStateCalled)
    }

    func test_stopConnection_expectHeartbeatTimerReset() async {
        // Setup
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        await sut.startConnection()
        await awaitCondition("the SSE service to connect") { self.sseServiceMock.connectCalled }

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

        // Action
        await sut.startConnection()

        // Wait for stream to be consumed
        await awaitCondition("SSE service to connect") { self.sseServiceMock.connectCalled }

        // Send connectionOpen event
        continuation.yield(.connectionOpen)
        await awaitCondition("the heartbeat timer to start") { self.heartbeatTimerMock.startTimerCalled }

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

        await sut.startConnection()
        await awaitCondition("SSE service to connect") { self.sseServiceMock.connectCalled }

        continuation.yield(.connectionOpen)
        continuation.yield(.serverEvent(ServerEvent(id: nil, type: "connected", data: "")))
        continuation.finish()

        await awaitCondition("the event stream to finish") { self.heartbeatTimerMock.resetCalled }

        XCTAssertEqual(counter.value, 1)
    }

    func test_transportOpenOnly_expectNoConnectionConfirmed() async {
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let counter = ConfirmationCounter()
        await sut.setOnConnectionConfirmed { counter.increment() }

        await sut.startConnection()
        await awaitCondition("SSE service to connect") { self.sseServiceMock.connectCalled }

        continuation.yield(.connectionOpen)
        continuation.finish()

        await awaitCondition("the event stream to finish") { self.heartbeatTimerMock.resetCalled }

        // Transport open alone is not confirmation: nothing should be backfilled yet.
        XCTAssertEqual(counter.value, 0)
    }

    func test_connectionOpen_expectRetryStateReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // Action
        await sut.startConnection()
        await awaitCondition("SSE service to connect") { self.sseServiceMock.connectCalled }

        continuation.yield(.connectionOpen)
        await awaitCondition("the retry state to reset") { self.retryHelperMock.resetRetryStateCalled }
        continuation.finish()

        // Assert
        XCTAssertTrue(retryHelperMock.resetRetryStateCalled)
    }

    func test_connectionFailed_givenRetryableError_expectRetryScheduled() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // Action
        await sut.startConnection()
        await awaitCondition("SSE service to connect") { self.sseServiceMock.connectCalled }

        let error = SseError.networkError(message: "Connection failed", underlyingError: nil)
        continuation.yield(.connectionFailed(error))
        await awaitCondition("the retry arguments to be recorded") {
            self.retryHelperMock.scheduleRetryReceivedArguments?.error == error
        }
        continuation.finish()

        // Assert
        XCTAssertTrue(retryHelperMock.scheduleRetryCalled)
        XCTAssertEqual(retryHelperMock.scheduleRetryReceivedArguments?.error, error)
    }

    func test_connectionFailed_expectHeartbeatTimerReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // Action
        await sut.startConnection()
        await awaitCondition("SSE service to connect") { self.sseServiceMock.connectCalled }

        continuation.yield(.connectionFailed(.networkError(message: "Error", underlyingError: nil)))
        await awaitCondition("the heartbeat timer to reset") { self.heartbeatTimerMock.resetCalled }
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.resetCalled)
    }

    func test_connectionClosed_expectHeartbeatTimerReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // Action
        await sut.startConnection()
        await awaitCondition("SSE service to connect") { self.sseServiceMock.connectCalled }

        continuation.yield(.connectionClosed)
        await awaitCondition("the heartbeat timer to reset") { self.heartbeatTimerMock.resetCalled }
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.resetCalled)
    }

    // MARK: - Server Event Tests

    func test_serverEvent_givenConnectedEvent_expectHeartbeatTimerStarted() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // Action
        await sut.startConnection()
        await awaitCondition("SSE service to connect") { self.sseServiceMock.connectCalled }

        let serverEvent = ServerEvent(id: nil, type: "connected", data: "{}")
        continuation.yield(.serverEvent(serverEvent))
        await awaitCondition("the heartbeat timer to start") { self.heartbeatTimerMock.startTimerCalled }
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.startTimerCalled)
    }

    func test_serverEvent_givenHeartbeatEvent_expectHeartbeatTimerRestarted() async {
        // Setup
        let (stream, streamContinuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // Action
        await sut.startConnection()
        await awaitCondition("SSE service to connect") { self.sseServiceMock.connectCalled }

        streamContinuation.yield(.connectionOpen)
        streamContinuation.yield(.serverEvent(ServerEvent(id: nil, type: "heartbeat", data: "{\"heartbeat\": 30}")))
        streamContinuation.finish()

        await awaitCondition("heartbeat timer to be started twice") {
            self.heartbeatTimerMock.startTimerCallsCount >= 2
        }

        // Assert: Timer started for connection open and again for heartbeat
        XCTAssertGreaterThanOrEqual(heartbeatTimerMock.startTimerCallsCount, 2)
    }

    func test_serverEvent_givenMessagesEvent_expectMessagesDispatched() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        inAppMessageManagerMock.dispatchClosure = { _, _ in Task {} }

        // Action
        await sut.startConnection()
        await awaitCondition("SSE service to connect") { self.sseServiceMock.connectCalled }

        // Create a valid messages event with proper JSON
        let messagesJson = """
        [{"queueId": "q1", "priority": 1, "messageId": "m1"}]
        """
        let messagesEvent = ServerEvent(id: nil, type: "messages", data: messagesJson)
        continuation.yield(.serverEvent(messagesEvent))
        continuation.finish()

        await awaitCondition("the event stream to finish") { self.heartbeatTimerMock.resetCalled }

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

        inAppMessageManagerMock.dispatchClosure = { _, _ in Task {} }

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
        await awaitCondition("SSE to be disabled") {
            self.inAppMessageManagerMock.dispatchReceivedInvocations.contains {
                if case .setSseEnabled(enabled: false) = $0.action { return true }
                return false
            }
        }
        await assertRemainsTrue("Max-retries handling dispatched the SSE-disable action more than once") {
            self.inAppMessageManagerMock.dispatchReceivedInvocations.filter {
                if case .setSseEnabled(enabled: false) = $0.action { return true }
                return false
            }.count == 1
        }

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

        inAppMessageManagerMock.dispatchClosure = { _, _ in Task {} }

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
        await awaitCondition("SSE to be disabled") {
            self.inAppMessageManagerMock.dispatchReceivedInvocations.contains {
                if case .setSseEnabled(enabled: false) = $0.action { return true }
                return false
            }
        }
        await assertRemainsTrue("Non-retryable handling dispatched the SSE-disable action more than once") {
            self.inAppMessageManagerMock.dispatchReceivedInvocations.filter {
                if case .setSseEnabled(enabled: false) = $0.action { return true }
                return false
            }.count == 1
        }

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
