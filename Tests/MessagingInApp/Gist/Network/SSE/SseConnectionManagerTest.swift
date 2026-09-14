@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioMessagingInAppMocks
@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

/// Tests for `SseConnectionManager` actor.
/// All tests use the March a49b5437 pattern: arm listener Task + withCheckedContinuation BEFORE
/// triggering SUT, then await the latched signal after triggering.
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
            try? await Task.sleep(nanoseconds: 5000000) // 0.005 seconds
        }
    }

    // MARK: - Start Connection Tests

    func test_startConnection_expectSseServiceConnectCalled() async {
        // Setup
        let (stream, streamContinuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        streamContinuation.finish()

        // ARM listener (March pattern)
        let connectReceived = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                sseServiceMock.connectClosure = { [stream] _, _ in
                    cont.resume()
                    return stream
                }
            }
        }

        // Action
        await sut.startConnection()
        await connectReceived.value

        // Assert
        XCTAssertTrue(sseServiceMock.connectCalled)
        XCTAssertEqual(sseServiceMock.connectCallsCount, 1)
    }

    func test_startConnection_givenAlreadyConnecting_expectNoSecondConnect() async {
        // Setup
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        // ARM listener for first connect
        let firstConnect = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                sseServiceMock.connectClosure = { [stream] _, _ in
                    cont.resume()
                    return stream
                }
            }
        }

        // Action: Start connection twice
        await sut.startConnection()
        await firstConnect.value

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

        // ARM listener
        let callbackSet = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                heartbeatTimerMock.setCallbackClosure = { _ in
                    cont.resume()
                }
            }
        }

        // Action
        await sut.startConnection()
        await callbackSet.value

        // Assert
        XCTAssertTrue(heartbeatTimerMock.setCallbackCalled)
    }

    // MARK: - Stop Connection Tests

    func test_stopConnection_expectSseServiceDisconnectCalled() async {
        // Setup
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        // ARM listener for connect
        let connected = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                sseServiceMock.connectClosure = { [stream] _, _ in
                    cont.resume()
                    return stream
                }
            }
        }

        await sut.startConnection()
        await connected.value

        // Action
        await sut.stopConnection()

        // Assert
        XCTAssertTrue(sseServiceMock.disconnectCalled)
    }

    func test_stopConnection_expectRetryStateReset() async {
        // Setup
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        let connected = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                sseServiceMock.connectClosure = { [stream] _, _ in
                    cont.resume()
                    return stream
                }
            }
        }

        await sut.startConnection()
        await connected.value

        // Action
        await sut.stopConnection()

        // Assert
        XCTAssertTrue(retryHelperMock.resetRetryStateCalled)
    }

    func test_stopConnection_expectHeartbeatTimerReset() async {
        // Setup
        let (stream, _) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        let connected = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                sseServiceMock.connectClosure = { [stream] _, _ in
                    cont.resume()
                    return stream
                }
            }
        }

        await sut.startConnection()
        await connected.value

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

        // ARM listener
        let timerStarted = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                heartbeatTimerMock.startTimerClosure = { _, _ in
                    cont.resume()
                }
            }
        }

        // Action
        await sut.startConnection()
        continuation.yield(.connectionOpen)

        await timerStarted.value
        continuation.finish()

        // Assert
        XCTAssertTrue(heartbeatTimerMock.startTimerCalled)
    }

    func test_openThenConnected_expectConnectionConfirmedExactlyOnce() async {
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let counter = ConfirmationCounter()
        await sut.setOnConnectionConfirmed { counter.increment() }

        // ARM listener for stream finish (reset is called when stream ends)
        let streamFinished = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                heartbeatTimerMock.resetClosure = { _ in
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

        let streamFinished = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                heartbeatTimerMock.resetClosure = { _ in
                    cont.resume()
                }
            }
        }

        await sut.startConnection()
        continuation.yield(.connectionOpen)
        continuation.finish()

        await streamFinished.value

        // Transport open alone is not confirmation
        XCTAssertEqual(counter.value, 0)
    }

    func test_connectionOpen_expectRetryStateReset() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let retryReset = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                retryHelperMock.resetRetryStateClosure = { _ in
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

        let retryScheduled = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                retryHelperMock.scheduleRetryClosure = { _, _ in
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

        let timerReset = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                heartbeatTimerMock.resetClosure = { _ in
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

        let timerReset = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                heartbeatTimerMock.resetClosure = { _ in
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

        let timerStarted = Task {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                heartbeatTimerMock.startTimerClosure = { _, _ in
                    cont.resume()
                }
            }
        }

        // Action
        await sut.startConnection()
        continuation.yield(.serverEvent(ServerEvent(id: nil, type: "connected", data: "{}")))

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

        // Assert
        XCTAssertGreaterThanOrEqual(heartbeatTimerMock.startTimerCallsCount, 2)
    }

    func test_serverEvent_givenMessagesEvent_expectMessagesDispatched() async {
        // Setup
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)
        sseServiceMock.connectReturnValue = stream

        let messagesDispatched = Task {
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
        let messagesJson = """
        [{"queueId": "q1", "priority": 1, "messageId": "m1"}]
        """
        continuation.yield(.serverEvent(ServerEvent(id: nil, type: "messages", data: messagesJson)))

        await messagesDispatched.value
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
        retryContinuation.yield((.maxRetriesReached, 1))

        await sseDisabled.value

        // Give a brief window for any duplicate dispatches
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
