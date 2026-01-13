@testable import CioInternalCommon
@testable import CioMessagingInApp
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

    // MARK: - Start Connection Tests

    func test_startConnection_expectSseServiceConnectCalled() async {
        // Setup: SSE service returns a stream that completes immediately
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream
        continuation.finish()

        // Action
        await sut.startConnection()

        // Allow time for the async task to start
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

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

        // Allow the first connection to start
        try? await Task.sleep(nanoseconds: 50000000) // 0.05 seconds

        await sut.startConnection()

        // Allow time for potential second connection
        try? await Task.sleep(nanoseconds: 50000000) // 0.05 seconds

        // Assert: Second call should not trigger another connect
        XCTAssertEqual(sseServiceMock.connectCallsCount, 1)
    }

    func test_startConnection_expectHeartbeatCallbackSet() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream
        continuation.finish()

        // Action
        await sut.startConnection()
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert
        XCTAssertTrue(heartbeatTimerMock.setCallbackCalled)
    }

    // MARK: - Stop Connection Tests

    func test_stopConnection_expectSseServiceDisconnectCalled() async {
        // Setup: Start a connection first
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        await sut.startConnection()
        try? await Task.sleep(nanoseconds: 50000000) // 0.05 seconds

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
        try? await Task.sleep(nanoseconds: 50000000) // 0.05 seconds

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
        try? await Task.sleep(nanoseconds: 50000000) // 0.05 seconds

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
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Clean up
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.startTimerCalled)
    }

    func test_connectionOpen_expectRetryStateReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // Action
        await sut.startConnection()
        continuation.yield(.connectionOpen)
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds
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
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds
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
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds
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
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds
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
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.startTimerCalled)
    }

    func test_serverEvent_givenHeartbeatEvent_expectHeartbeatTimerRestarted() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // Action
        await sut.startConnection()

        // First establish connection
        continuation.yield(.connectionOpen)
        try? await Task.sleep(nanoseconds: 50000000) // 0.05 seconds

        // Then receive heartbeat
        let heartbeatEvent = ServerEvent(id: nil, type: "heartbeat", data: "{\"heartbeat\": 30}")
        continuation.yield(.serverEvent(heartbeatEvent))
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds
        continuation.finish()

        // Assert: Timer should be started multiple times (once for connection, once for heartbeat)
        XCTAssertGreaterThanOrEqual(heartbeatTimerMock.startTimerCallsCount, 2)
    }

    func test_serverEvent_givenMessagesEvent_expectMessagesDispatched() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        var dispatchedActions: [InAppMessageAction] = []
        inAppMessageManagerMock.dispatchClosure = { action, _ in
            dispatchedActions.append(action)
            return Task {}
        }

        // Action
        await sut.startConnection()

        // Create a valid messages event with proper JSON
        let messagesJson = """
        [{"queueId": "q1", "priority": 1, "messageId": "m1"}]
        """
        let messagesEvent = ServerEvent(id: nil, type: "messages", data: messagesJson)
        continuation.yield(.serverEvent(messagesEvent))
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds
        continuation.finish()

        // Assert: Check if processMessageQueue action was dispatched
        let processActions = dispatchedActions.filter {
            if case .processMessageQueue = $0 { return true }
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

        var dispatchedActions: [InAppMessageAction] = []
        inAppMessageManagerMock.dispatchClosure = { action, _ in
            dispatchedActions.append(action)
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
        try? await Task.sleep(nanoseconds: 50000000) // 0.05 seconds

        // Emit maxRetriesReached decision (with generation 1)
        retryContinuation.yield((.maxRetriesReached, 1))
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Clean up
        sseContinuation.finish()
        retryContinuation.finish()

        // Assert: Check that SSE was disabled (fallback to polling)
        let sseDisabledActions = dispatchedActions.filter {
            if case .setSseEnabled(enabled: false) = $0 { return true }
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

        var dispatchedActions: [InAppMessageAction] = []
        inAppMessageManagerMock.dispatchClosure = { action, _ in
            dispatchedActions.append(action)
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
        try? await Task.sleep(nanoseconds: 50000000) // 0.05 seconds

        retryContinuation.yield((.retryNotPossible, 1))
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        sseContinuation.finish()
        retryContinuation.finish()

        // Assert
        let sseDisabledActions = dispatchedActions.filter {
            if case .setSseEnabled(enabled: false) = $0 { return true }
            return false
        }
        XCTAssertEqual(sseDisabledActions.count, 1)
    }
}
