@testable import CioInternalCommon
@testable import CioMessagingInApp
import SharedTests
import XCTest

/// Tests for `CioSseLifecycleManager` actor.
class SseLifecycleManagerTest: XCTestCase {
    private var loggerMock: LoggerMock!
    private var inAppMessageManagerMock: InAppMessageManagerMock!
    private var sseConnectionManagerMock: SseConnectionManagerProtocolMock!

    private var sut: CioSseLifecycleManager!

    override func setUp() {
        super.setUp()
        loggerMock = LoggerMock()
        inAppMessageManagerMock = InAppMessageManagerMock()
        sseConnectionManagerMock = SseConnectionManagerProtocolMock()

        // Setup default return value for subscribe
        inAppMessageManagerMock.subscribeReturnValue = Task {}
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func createLifecycleManager() -> CioSseLifecycleManager {
        CioSseLifecycleManager(
            logger: loggerMock,
            inAppMessageManager: inAppMessageManagerMock,
            sseConnectionManager: sseConnectionManagerMock
        )
    }

    private func setupDefaultState(useSse: Bool = false) {
        inAppMessageManagerMock.underlyingState = InAppMessageState(
            siteId: "test-site-id",
            dataCenter: "us",
            environment: .production,
            userId: "test-user",
            useSse: useSse
        )
    }

    /// Triggers the SSE flag change subscriber with a new state
    private func triggerSseFlagChange(useSse: Bool) {
        let newState = InAppMessageState(
            siteId: "test-site-id",
            dataCenter: "us",
            environment: .production,
            userId: "test-user",
            useSse: useSse
        )
        inAppMessageManagerMock.underlyingState = newState
        inAppMessageManagerMock.subscribeReceivedArguments?.subscriber.newState(state: newState)
    }

    // MARK: - Initial State Tests (App Foreground at Startup)

    func test_start_givenAppInForegroundAndSseEnabled_expectConnectionStarted() async {
        // Setup: SSE enabled and app in foreground (default state on test device)
        setupDefaultState(useSse: true)
        sut = createLifecycleManager()

        // Action
        await sut.start()

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: Connection should be started
        XCTAssertTrue(sseConnectionManagerMock.startConnectionCalled)
        XCTAssertEqual(sseConnectionManagerMock.startConnectionCallsCount, 1)
    }

    func test_start_givenAppInForegroundAndSseDisabled_expectNoConnection() async {
        // Setup: SSE disabled
        setupDefaultState(useSse: false)
        sut = createLifecycleManager()

        // Action
        await sut.start()

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: Connection should NOT be started
        XCTAssertFalse(sseConnectionManagerMock.startConnectionCalled)
    }

    // MARK: - Foreground Transition Tests

    func test_foregroundNotification_givenSseEnabled_expectConnectionStarted() async {
        // Setup: Start with SSE enabled
        setupDefaultState(useSse: true)
        sut = createLifecycleManager()
        await sut.start()

        // Reset mock to track only foreground-triggered calls
        // First, the initial start() may have called startConnection, so we reset
        sseConnectionManagerMock.resetMock()

        // Simulate app going to background first
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds
        sseConnectionManagerMock.resetMock()

        // Action: Simulate foreground notification
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert
        XCTAssertTrue(sseConnectionManagerMock.startConnectionCalled)
        XCTAssertEqual(sseConnectionManagerMock.startConnectionCallsCount, 1)
    }

    func test_foregroundNotification_givenSseDisabled_expectNoConnection() async {
        // Setup: SSE disabled
        setupDefaultState(useSse: false)
        sut = createLifecycleManager()
        await sut.start()

        // Simulate app going to background first
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds
        sseConnectionManagerMock.resetMock()

        // Action: Simulate foreground notification
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: No connection should be started
        XCTAssertFalse(sseConnectionManagerMock.startConnectionCalled)
    }

    func test_foregroundNotification_givenAlreadyForegrounded_expectSkipped() async {
        // Setup: SSE enabled
        setupDefaultState(useSse: true)
        sut = createLifecycleManager()
        await sut.start()

        // Reset mock after initial start
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds
        sseConnectionManagerMock.resetMock()

        // Action: Send foreground notification while already foregrounded
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: Should be skipped since already foregrounded
        XCTAssertFalse(sseConnectionManagerMock.startConnectionCalled)
    }

    // MARK: - Background Transition Tests

    func test_backgroundNotification_givenSseEnabled_expectConnectionStopped() async {
        // Setup: SSE enabled
        setupDefaultState(useSse: true)
        sut = createLifecycleManager()
        await sut.start()
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Action: Simulate background notification
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert
        XCTAssertTrue(sseConnectionManagerMock.stopConnectionCalled)
        XCTAssertEqual(sseConnectionManagerMock.stopConnectionCallsCount, 1)
    }

    func test_backgroundNotification_givenSseDisabled_expectNoStopConnection() async {
        // Setup: SSE disabled
        setupDefaultState(useSse: false)
        sut = createLifecycleManager()
        await sut.start()
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Action: Simulate background notification
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: No stop should be called
        XCTAssertFalse(sseConnectionManagerMock.stopConnectionCalled)
    }

    func test_backgroundNotification_givenAlreadyBackgrounded_expectSkipped() async {
        // Setup: SSE enabled
        setupDefaultState(useSse: true)
        sut = createLifecycleManager()
        await sut.start()

        // First background
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds
        sseConnectionManagerMock.resetMock()

        // Action: Send another background notification
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: Should be skipped since already backgrounded
        XCTAssertFalse(sseConnectionManagerMock.stopConnectionCalled)
    }

    // MARK: - SSE Flag Change Tests

    func test_sseFlagChangedToTrue_givenForegrounded_expectConnectionStarted() async {
        // Setup: SSE initially disabled
        setupDefaultState(useSse: false)
        sut = createLifecycleManager()
        await sut.start()
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Verify no connection started initially
        XCTAssertFalse(sseConnectionManagerMock.startConnectionCalled)

        // Action: Change SSE flag to true (simulating server enabling SSE)
        triggerSseFlagChange(useSse: true)

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert
        XCTAssertTrue(sseConnectionManagerMock.startConnectionCalled)
    }

    func test_sseFlagChangedToFalse_givenForegrounded_expectConnectionStopped() async {
        // Setup: SSE initially enabled
        setupDefaultState(useSse: true)
        sut = createLifecycleManager()
        await sut.start()
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Reset mock after initial connection
        sseConnectionManagerMock.resetMock()

        // Action: Change SSE flag to false
        triggerSseFlagChange(useSse: false)

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert
        XCTAssertTrue(sseConnectionManagerMock.stopConnectionCalled)
    }

    func test_sseFlagChanged_givenBackgrounded_expectDeferredAction() async {
        // Setup: SSE initially disabled
        setupDefaultState(useSse: false)
        sut = createLifecycleManager()
        await sut.start()

        // Go to background
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds
        sseConnectionManagerMock.resetMock()

        // Action: Change SSE flag to true while backgrounded
        triggerSseFlagChange(useSse: true)

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: No connection should be started while backgrounded
        XCTAssertFalse(sseConnectionManagerMock.startConnectionCalled)

        // Action: Now foreground the app
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: Connection should be started now
        XCTAssertTrue(sseConnectionManagerMock.startConnectionCalled)
    }

    // MARK: - Full Lifecycle Flow Tests

    func test_fullLifecycleFlow_foregroundBackgroundForeground() async {
        // Setup: SSE enabled
        setupDefaultState(useSse: true)
        sut = createLifecycleManager()
        await sut.start()
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Verify: Initial connection started
        XCTAssertEqual(sseConnectionManagerMock.startConnectionCallsCount, 1)
        XCTAssertEqual(sseConnectionManagerMock.stopConnectionCallsCount, 0)

        // Action: Go to background
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Verify: Connection stopped
        XCTAssertEqual(sseConnectionManagerMock.startConnectionCallsCount, 1)
        XCTAssertEqual(sseConnectionManagerMock.stopConnectionCallsCount, 1)

        // Action: Return to foreground
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Verify: Connection started again
        XCTAssertEqual(sseConnectionManagerMock.startConnectionCallsCount, 2)
        XCTAssertEqual(sseConnectionManagerMock.stopConnectionCallsCount, 1)
    }
}
