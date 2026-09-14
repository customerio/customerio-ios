@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioMessagingInAppMocks
@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

/// Tests for `SseConnectionManager` actor.
/// All async tests use the March a49b5437 pattern: arm a listener Task BEFORE triggering the SUT,
/// then await task.value after. This yields the cooperative pool correctly and avoids flakiness.
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
        let (stream, streamContinuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        streamContinuation.finish()

        // ARM listener as Task BEFORE triggering SUT (March a49b5437 pattern)
        let connectReceived = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                sseServiceMock.connectClosure = { [stream] _, _ in
                    cont.resume()
                    return stream
                }
            }
        }

        // Action: trigger SUT
        await sut.startConnection()

        // Await the latched signal (yields cooperative pool, lets SUT's internal Task run)
        await connectReceived.value

        // Assert
        XCTAssertTrue(sseServiceMock.connectCalled)
        XCTAssertEqual(sseServiceMock.connectCallsCount, 1)
    }

    func test_startConnection_givenAlreadyConnecting_expectNoSecondConnect() async {
        // Setup: SSE service returns a stream that doesn't complete (simulating ongoing connection)
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        // ARM listener for first connect
        let firstConnectReceived = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                sseServiceMock.connectClosure = { [stream] _, _ in
                    cont.resume()
                    return stream
                }
            }
        }

        // Action: Start connection twice
        await sut.startConnection()
        await firstConnectReceived.value

        // Second startConnection should be a no-op
        await sut.startConnection()

        // Brief yield to let any wrongly spawned task become visible
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms observation window

        // Assert: only one connect call
        XCTAssertEqual(sseServiceMock.connectCallsCount, 1)
    }

    func test_startConnection_expectHeartbeatCallbackSet() async {
        // Setup
        let (stream, streamContinuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        streamContinuation.finish()

        // ARM listener for setCallback
        let callbackSet = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                heartbeatTimerMock.setCallbackClosure = { _ in
                    cont.resume()
                }
            }
        }

        // ARM connect to return the stream
        sseServiceMock.connectClosure = { [stream] _, _ in stream }

        // Action
        await sut.startConnection()
        await callbackSet.value

        // Assert
        XCTAssertTrue(heartbeatTimerMock.setCallbackCalled)
    }

    // MARK: - Stop Connection Tests

    func test_stopConnection_expectSseServiceDisconnectCalled() async {
        // Setup: Start a connection first
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        // ARM listener for connect
        let connectReceived = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                sseServiceMock.connectClosure = { [stream] _, _ in
                    cont.resume()
                    return stream
                }
            }
        }

        await sut.startConnection()
        await connectReceived.value

        // Action
        await sut.stopConnection()

        // Assert
        XCTAssertTrue(sseServiceMock.disconnectCalled)
    }

    func test_stopConnection_expectRetryStateReset() async {
        // Setup
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        let connectReceived = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                sseServiceMock.connectClosure = { [stream] _, _ in
                    cont.resume()
                    return stream
                }
            }
        }

        await sut.startConnection()
        await connectReceived.value

        // Action
        await sut.stopConnection()

        // Assert
        XCTAssertTrue(retryHelperMock.resetRetryStateCalled)
    }

    func test_stopConnection_expectHeartbeatTimerReset() async {
        // Setup
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        let connectReceived = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                sseServiceMock.connectClosure = { [stream] _, _ in
                    cont.resume()
                    return stream
                }
            }
        }

        await sut.startConnection()
        await connectReceived.value

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

        // ARM listener for startTimer
        let timerStarted = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                heartbeatTimerMock.startTimerClosure = { _, _ in
                    cont.resume()
                }
            }
        }

        // Action
        await sut.startConnection()

        // Send connectionOpen event
        continuation.yield(.connectionOpen)

        // Wait for timer to start
        await timerStarted.value

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

        // ARM listener for heartbeat reset (signals stream finished processing)
        let streamFinished = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                heartbeatTimerMock.resetClosure = {
                    cont.resume()
                }
            }
        }

        await sut.startConnection()
        continuation.yield(.connectionOpen)
        continuation.yield(.serverEvent(ServerEvent(id: nil, type: "connected", data: "")))
        continuation.finish()

        await streamFinished.value

        XCTAssertEqual(counter.value, 1)
    }

    func test_transportOpenOnly_expectNoConnectionConfirmed() async {
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let counter = ConfirmationCounter()
        await sut.setOnConnectionConfirmed { counter.increment() }

        // ARM listener for heartbeat reset (signals stream finished processing)
        let streamFinished = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                heartbeatTimerMock.resetClosure = {
                    cont.resume()
                }
            }
        }

        await sut.startConnection()
        continuation.yield(.connectionOpen)
        continuation.finish()

        await streamFinished.value

        // Transport open alone is not confirmation: nothing should be backfilled yet.
        XCTAssertEqual(counter.value, 0)
    }

    func test_connectionOpen_expectRetryStateReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // ARM listener for retry state reset
        let retryReset = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                retryHelperMock.resetRetryStateClosure = {
                    cont.resume()
                }
            }
        }

        // Action
        await sut.startConnection()
        continuation.yield(.connectionOpen)

        await retryReset.value
        continuation.finish()

        // Assert
        XCTAssertTrue(retryHelperMock.resetRetryStateCalled)
    }

    func test_connectionFailed_givenRetryableError_expectRetryScheduled() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let error = SseError.networkError(message: "Connection failed", underlyingError: nil)

        // ARM listener for scheduleRetry
        let retryScheduled = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                retryHelperMock.scheduleRetryClosure = { _ in
                    cont.resume()
                }
            }
        }

        // Action
        await sut.startConnection()
        continuation.yield(.connectionFailed(error))

        await retryScheduled.value
        continuation.finish()

        // Assert
        XCTAssertTrue(retryHelperMock.scheduleRetryCalled)
        XCTAssertEqual(retryHelperMock.scheduleRetryReceivedArguments?.error, error)
    }

    func test_connectionFailed_expectHeartbeatTimerReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // ARM listener for heartbeat reset
        let timerReset = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                heartbeatTimerMock.resetClosure = {
                    cont.resume()
                }
            }
        }

        // Action
        await sut.startConnection()
        continuation.yield(.connectionFailed(.networkError(message: "Error", underlyingError: nil)))

        await timerReset.value
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.resetCalled)
    }

    func test_connectionClosed_expectHeartbeatTimerReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // ARM listener for heartbeat reset
        let timerReset = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                heartbeatTimerMock.resetClosure = {
                    cont.resume()
                }
            }
        }

        // Action
        await sut.startConnection()
        continuation.yield(.connectionClosed)

        await timerReset.value
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.resetCalled)
    }

    // MARK: - Server Event Tests

    func test_serverEvent_givenConnectedEvent_expectHeartbeatTimerStarted() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // ARM listener for startTimer
        let timerStarted = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                heartbeatTimerMock.startTimerClosure = { _, _ in
                    cont.resume()
                }
            }
        }

        // Action
        await sut.startConnection()

        let serverEvent = ServerEvent(id: nil, type: "connected", data: "{}")
        continuation.yield(.serverEvent(serverEvent))

        await timerStarted.value
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.startTimerCalled)
    }

    func test_serverEvent_givenHeartbeatEvent_expectHeartbeatTimerRestarted() async {
        // Setup: resume when startTimer is called the second time
        let (stream, streamContinuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let secondStartTimerReceived = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                heartbeatTimerMock.startTimerClosure = { [weak heartbeatTimerMock] _, _ in
                    guard let mock = heartbeatTimerMock, mock.startTimerCallsCount == 2 else { return }
                    cont.resume()
                }
            }
        }

        // Action
        await sut.startConnection()
        streamContinuation.yield(.connectionOpen)
        streamContinuation.yield(.serverEvent(ServerEvent(id: nil, type: "heartbeat", data: "{\"heartbeat\": 30}")))
        streamContinuation.finish()

        await secondStartTimerReceived.value

        // Assert: Timer started for connection open and again for heartbeat
        XCTAssertGreaterThanOrEqual(heartbeatTimerMock.startTimerCallsCount, 2)
    }

    func test_serverEvent_givenMessagesEvent_expectMessagesDispatched() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        // ARM listener for dispatch
        let dispatched = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                inAppMessageManagerMock.dispatchClosure = { action, _ in
                    if case .processMessageQueue = action {
                        cont.resume()
                    }
                    return Task {}
                }
            }
        }

        // Action
        await sut.startConnection()

        // Create a valid messages event with proper JSON
        let messagesJson = """
        [{"queueId": "q1", "priority": 1, "messageId": "m1"}]
        """
        let messagesEvent = ServerEvent(id: nil, type: "messages", data: messagesJson)
        continuation.yield(.serverEvent(messagesEvent))

        await dispatched.value
        continuation.finish()

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

        // Create a fresh SUT with the mocked retry stream
        sut = SseConnectionManager(
            logger: loggerMock,
            inAppMessageManager: inAppMessageManagerMock,
            sseService: sseServiceMock,
            retryHelper: retryHelperMock,
            heartbeatTimer: heartbeatTimerMock
        )

        // ARM listener for SSE disable dispatch
        let sseDisabled = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                inAppMessageManagerMock.dispatchClosure = { action, _ in
                    if case .setSseEnabled(enabled: false) = action {
                        cont.resume()
                    }
                    return Task {}
                }
            }
        }

        // Action
        await sut.startConnection()

        // Emit maxRetriesReached decision (with generation 1)
        retryContinuation.yield((.maxRetriesReached, 1))

        await sseDisabled.value

        // Brief observation window to catch any duplicate dispatches
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Clean up
        sseContinuation.finish()
        retryContinuation.finish()

        // Assert: Check that SSE was disabled exactly once (fallback to polling)
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

        // ARM listener for SSE disable dispatch
        let sseDisabled = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                inAppMessageManagerMock.dispatchClosure = { action, _ in
                    if case .setSseEnabled(enabled: false) = action {
                        cont.resume()
                    }
                    return Task {}
                }
            }
        }

        // Action
        await sut.startConnection()

        retryContinuation.yield((.retryNotPossible, 1))

        await sseDisabled.value

        // Brief observation window
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

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
