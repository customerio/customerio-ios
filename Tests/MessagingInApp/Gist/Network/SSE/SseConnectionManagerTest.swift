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

    /// Polls synchronized test state until the async SSE task reaches the expected point.
    private func waitUntil(
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) async {
        for _ in 0 ..< 100 {
            if condition() { return }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10000000) // 0.01 seconds
        }
        XCTFail("Timed out waiting for \(message)", file: file, line: line)
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
            try? await Task.sleep(nanoseconds: 5000000) // 0.005 seconds
        }
    }

    // MARK: - Start Connection Tests

    func test_startConnection_expectSseServiceConnectCalled() async {
        // Setup: SSE service returns a stream that completes immediately
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream
        continuation.finish()

        // Action
        await sut.startConnection()

        await waitUntil("the SSE service to connect") { sseServiceMock.connectCalled }

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

        await waitUntil("the first SSE connection") { sseServiceMock.connectCallsCount == 1 }

        await sut.startConnection()

        // Assert: Give any wrongly spawned connection task a bounded window to become visible.
        await assertRemainsTrue("Starting an active connection scheduled a second SSE connection") {
            sseServiceMock.connectCallsCount == 1
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
        await waitUntil("the heartbeat callback") { heartbeatTimerMock.setCallbackCalled }

        // Assert
        XCTAssertTrue(heartbeatTimerMock.setCallbackCalled)
    }

    // MARK: - Stop Connection Tests

    func test_stopConnection_expectSseServiceDisconnectCalled() async {
        // Setup: Start a connection first
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        await sut.startConnection()
        await waitUntil("the SSE service to connect") { sseServiceMock.connectCalled }

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
        await waitUntil("the SSE service to connect") { sseServiceMock.connectCalled }

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
        await waitUntil("the SSE service to connect") { sseServiceMock.connectCalled }

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

        // Send connectionOpen event
        continuation.yield(.connectionOpen)
        await waitUntil("the heartbeat timer to start") { heartbeatTimerMock.startTimerCalled }

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
        continuation.yield(.connectionOpen)
        continuation.yield(.serverEvent(ServerEvent(id: nil, type: "connected", data: "")))
        continuation.finish()
        await waitUntil("the event stream to finish") { heartbeatTimerMock.resetCalled }

        XCTAssertEqual(counter.value, 1)
    }

    func test_transportOpenOnly_expectNoConnectionConfirmed() async {
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let counter = ConfirmationCounter()
        await sut.setOnConnectionConfirmed { counter.increment() }

        await sut.startConnection()
        continuation.yield(.connectionOpen)
        continuation.finish()
        await waitUntil("the event stream to finish") { heartbeatTimerMock.resetCalled }

        // Transport open alone is not confirmation: nothing should be backfilled yet.
        XCTAssertEqual(counter.value, 0)
    }

    func test_connectionOpen_expectRetryStateReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // Action
        await sut.startConnection()
        continuation.yield(.connectionOpen)
        await waitUntil("the retry state to reset") { retryHelperMock.resetRetryStateCalled }
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

        let error = SseError.networkError(message: "Connection failed", underlyingError: nil)
        continuation.yield(.connectionFailed(error))
        await waitUntil("the retry arguments to be recorded") {
            retryHelperMock.scheduleRetryReceivedArguments?.error == error
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
        continuation.yield(.connectionFailed(.networkError(message: "Error", underlyingError: nil)))
        await waitUntil("the heartbeat timer to reset") { heartbeatTimerMock.resetCalled }
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
        continuation.yield(.connectionClosed)
        await waitUntil("the heartbeat timer to reset") { heartbeatTimerMock.resetCalled }
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

        let serverEvent = ServerEvent(id: nil, type: "connected", data: "{}")
        continuation.yield(.serverEvent(serverEvent))
        await waitUntil("the heartbeat timer to start") { heartbeatTimerMock.startTimerCalled }
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

        await fulfillment(of: [heartbeatTimerStartedTwice], timeout: 1.0)

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

        // Create a valid messages event with proper JSON
        let messagesJson = """
        [{"queueId": "q1", "priority": 1, "messageId": "m1"}]
        """
        let messagesEvent = ServerEvent(id: nil, type: "messages", data: messagesJson)
        continuation.yield(.serverEvent(messagesEvent))
        continuation.finish()
        await waitUntil("the event stream to finish") { heartbeatTimerMock.resetCalled }

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
        await waitUntil("SSE to be disabled") {
            inAppMessageManagerMock.dispatchReceivedInvocations.contains {
                if case .setSseEnabled(enabled: false) = $0.action { return true }
                return false
            }
        }
        await assertRemainsTrue("Max-retries handling dispatched the SSE-disable action more than once") {
            inAppMessageManagerMock.dispatchReceivedInvocations.filter {
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
        await waitUntil("SSE to be disabled") {
            inAppMessageManagerMock.dispatchReceivedInvocations.contains {
                if case .setSseEnabled(enabled: false) = $0.action { return true }
                return false
            }
        }
        await assertRemainsTrue("Non-retryable handling dispatched the SSE-disable action more than once") {
            inAppMessageManagerMock.dispatchReceivedInvocations.filter {
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
