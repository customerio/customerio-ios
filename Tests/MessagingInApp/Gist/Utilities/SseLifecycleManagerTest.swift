@testable import CioInternalCommon
@testable import CioMessagingInApp
import SharedTests
import UIKit
import XCTest

/// Tests for `CioSseLifecycleManager` actor.
class SseLifecycleManagerTest: XCTestCase {
    private var loggerMock: LoggerMock!
    private var inAppMessageManagerMock: InAppMessageManagerMock!
    private var sseConnectionManagerMock: SseConnectionManagerProtocolMock!
    private var applicationStateProviderMock: ApplicationStateProviderMock!

    private var sut: CioSseLifecycleManager!

    override func setUp() {
        super.setUp()
        loggerMock = LoggerMock()
        inAppMessageManagerMock = InAppMessageManagerMock()
        sseConnectionManagerMock = SseConnectionManagerProtocolMock()
        applicationStateProviderMock = ApplicationStateProviderMock()

        // Default to foreground state for most tests (explicit control)
        applicationStateProviderMock.underlyingApplicationState = .active

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
            sseConnectionManager: sseConnectionManagerMock,
            applicationStateProvider: applicationStateProviderMock
        )
    }

    /// Sets up the default state for the InAppMessageManager mock
    /// - Parameters:
    ///   - useSse: Whether SSE is enabled (from server header)
    ///   - userId: The userId (nil for anonymous users)
    private func setupDefaultState(useSse: Bool = false, userId: String? = "test-user") {
        inAppMessageManagerMock.underlyingState = InAppMessageState(
            siteId: "test-site-id",
            dataCenter: "us",
            environment: .production,
            userId: userId,
            useSse: useSse
        )
    }

    /// Triggers the SSE flag change subscriber with a new state.
    /// The lifecycle manager registers subscribers in order: SSE flag (index 0), userId (index 1).
    private func triggerSseFlagChange(useSse: Bool, userId: String? = "test-user") {
        let newState = InAppMessageState(
            siteId: "test-site-id",
            dataCenter: "us",
            environment: .production,
            userId: userId,
            useSse: useSse
        )
        inAppMessageManagerMock.underlyingState = newState
        // SSE flag subscriber is registered first (index 0)
        guard !inAppMessageManagerMock.subscribeReceivedInvocations.isEmpty else { return }
        inAppMessageManagerMock.subscribeReceivedInvocations[0].subscriber.newState(state: newState)
    }

    /// Triggers the userId change subscriber with a new state.
    /// The lifecycle manager registers subscribers in order: SSE flag (index 0), userId (index 1).
    private func triggerUserIdChange(userId: String?, useSse: Bool = false) {
        let newState = InAppMessageState(
            siteId: "test-site-id",
            dataCenter: "us",
            environment: .production,
            userId: userId,
            useSse: useSse
        )
        inAppMessageManagerMock.underlyingState = newState
        // userId subscriber is registered second (index 1)
        guard inAppMessageManagerMock.subscribeReceivedInvocations.count > 1 else { return }
        inAppMessageManagerMock.subscribeReceivedInvocations[1].subscriber.newState(state: newState)
    }

    // MARK: - Initial State Tests (App Foreground at Startup)

    func test_start_givenAppInForegroundAndSseEnabled_expectConnectionStarted() async {
        // Setup: SSE enabled and app explicitly set to foreground
        applicationStateProviderMock.underlyingApplicationState = .active
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
        // Setup: SSE disabled, app in foreground
        applicationStateProviderMock.underlyingApplicationState = .active
        setupDefaultState(useSse: false)
        sut = createLifecycleManager()

        // Action
        await sut.start()

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: Connection should NOT be started
        XCTAssertFalse(sseConnectionManagerMock.startConnectionCalled)
    }

    // MARK: - Initial State Tests (App Background at Startup)

    func test_start_givenAppInBackgroundAndSseEnabled_expectNoConnection() async {
        // Setup: SSE enabled but app is in background (e.g., background fetch, push extension)
        applicationStateProviderMock.underlyingApplicationState = .background
        setupDefaultState(useSse: true)
        sut = createLifecycleManager()

        // Action
        await sut.start()

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: Connection should NOT be started when app is backgrounded
        XCTAssertFalse(sseConnectionManagerMock.startConnectionCalled)
    }

    func test_start_givenAppInBackgroundAndSseDisabled_expectNoConnection() async {
        // Setup: SSE disabled and app in background
        applicationStateProviderMock.underlyingApplicationState = .background
        setupDefaultState(useSse: false)
        sut = createLifecycleManager()

        // Action
        await sut.start()

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: Connection should NOT be started
        XCTAssertFalse(sseConnectionManagerMock.startConnectionCalled)
    }

    func test_start_givenAppInInactiveStateAndSseEnabled_expectConnectionStarted() async {
        // Setup: SSE enabled and app is inactive (transitioning, but not background)
        // Inactive is treated as foreground since it's not .background
        applicationStateProviderMock.underlyingApplicationState = .inactive
        setupDefaultState(useSse: true)
        sut = createLifecycleManager()

        // Action
        await sut.start()

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: Connection should be started (inactive is not background)
        XCTAssertTrue(sseConnectionManagerMock.startConnectionCalled)
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

    func test_backgroundNotification_givenSseDisabled_expectStopConnectionCalledAnyway() async {
        // Setup: SSE disabled
        setupDefaultState(useSse: false)
        sut = createLifecycleManager()
        await sut.start()
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Action: Simulate background notification
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: stopConnection is always called when backgrounding (matching Android behavior)
        // stopConnection() is idempotent, safe to call even if not connected
        XCTAssertTrue(sseConnectionManagerMock.stopConnectionCalled)
        XCTAssertEqual(sseConnectionManagerMock.stopConnectionCallsCount, 1)
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

    // MARK: - Anonymous User Tests (SSE requires identified user)

    func test_start_givenSseEnabledButAnonymousUser_expectNoConnection() async {
        // Setup: SSE enabled but user is anonymous (no userId)
        setupDefaultState(useSse: true, userId: nil)
        sut = createLifecycleManager()

        // Action
        await sut.start()

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: Connection should NOT be started for anonymous users
        XCTAssertFalse(sseConnectionManagerMock.startConnectionCalled)
    }

    func test_foregroundNotification_givenSseEnabledButAnonymousUser_expectNoConnection() async {
        // Setup: SSE enabled but user is anonymous
        setupDefaultState(useSse: true, userId: nil)
        sut = createLifecycleManager()
        await sut.start()

        // Simulate going to background and back to foreground
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds
        sseConnectionManagerMock.resetMock()

        // Action: Simulate foreground notification
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: No connection should be started for anonymous users
        XCTAssertFalse(sseConnectionManagerMock.startConnectionCalled)
    }

    func test_sseFlagChangedToTrue_givenAnonymousUser_expectNoConnection() async {
        // Setup: SSE initially disabled, user is anonymous
        setupDefaultState(useSse: false, userId: nil)
        sut = createLifecycleManager()
        await sut.start()
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Verify no connection started initially
        XCTAssertFalse(sseConnectionManagerMock.startConnectionCalled)

        // Action: Change SSE flag to true (simulating server enabling SSE)
        triggerSseFlagChange(useSse: true, userId: nil)

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: Still no connection because user is anonymous
        XCTAssertFalse(sseConnectionManagerMock.startConnectionCalled)
    }

    // MARK: - User Identification Change Tests

    func test_userBecomesIdentified_givenSseEnabled_expectConnectionStarted() async {
        // Setup: SSE enabled but user is initially anonymous
        setupDefaultState(useSse: true, userId: nil)
        sut = createLifecycleManager()
        await sut.start()
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Verify no connection started initially
        XCTAssertFalse(sseConnectionManagerMock.startConnectionCalled)

        // Action: User becomes identified
        triggerUserIdChange(userId: "new-identified-user", useSse: true)

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: Connection should now be started
        XCTAssertTrue(sseConnectionManagerMock.startConnectionCalled)
        XCTAssertEqual(sseConnectionManagerMock.startConnectionCallsCount, 1)
    }

    func test_userBecomesAnonymous_givenSseEnabledAndConnected_expectConnectionStopped() async {
        // Setup: SSE enabled and user is identified
        setupDefaultState(useSse: true, userId: "test-user")
        sut = createLifecycleManager()
        await sut.start()
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Verify connection started initially
        XCTAssertTrue(sseConnectionManagerMock.startConnectionCalled)
        XCTAssertEqual(sseConnectionManagerMock.startConnectionCallsCount, 1)

        // Action: User becomes anonymous (e.g., logout)
        triggerUserIdChange(userId: nil, useSse: true)

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: Connection should be stopped
        XCTAssertTrue(sseConnectionManagerMock.stopConnectionCalled)
        XCTAssertEqual(sseConnectionManagerMock.stopConnectionCallsCount, 1)
    }

    func test_userBecomesIdentified_givenSseDisabled_expectNoConnection() async {
        // Setup: SSE disabled, user is anonymous
        setupDefaultState(useSse: false, userId: nil)
        sut = createLifecycleManager()
        await sut.start()
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Action: User becomes identified but SSE is still disabled
        triggerUserIdChange(userId: "new-identified-user", useSse: false)

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: No connection because SSE flag is disabled
        XCTAssertFalse(sseConnectionManagerMock.startConnectionCalled)
    }

    func test_userBecomesIdentified_givenBackgrounded_expectDeferredConnection() async {
        // Setup: SSE enabled, user is anonymous
        setupDefaultState(useSse: true, userId: nil)
        sut = createLifecycleManager()
        await sut.start()

        // Go to background
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds
        sseConnectionManagerMock.resetMock()

        // Action: User becomes identified while backgrounded
        triggerUserIdChange(userId: "new-identified-user", useSse: true)

        // Allow time for async operations
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: No connection while backgrounded
        XCTAssertFalse(sseConnectionManagerMock.startConnectionCalled)

        // Action: Return to foreground
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: Connection should now be started
        XCTAssertTrue(sseConnectionManagerMock.startConnectionCalled)
    }

    // MARK: - Combined State Change Tests

    func test_fullFlow_anonymousToIdentifiedToAnonymous() async {
        // Setup: SSE enabled, user is anonymous
        setupDefaultState(useSse: true, userId: nil)
        sut = createLifecycleManager()
        await sut.start()
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Verify: No initial connection (anonymous user)
        XCTAssertEqual(sseConnectionManagerMock.startConnectionCallsCount, 0)
        XCTAssertEqual(sseConnectionManagerMock.stopConnectionCallsCount, 0)

        // Action: User logs in (becomes identified)
        triggerUserIdChange(userId: "logged-in-user", useSse: true)
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Verify: Connection started
        XCTAssertEqual(sseConnectionManagerMock.startConnectionCallsCount, 1)
        XCTAssertEqual(sseConnectionManagerMock.stopConnectionCallsCount, 0)

        // Action: User logs out (becomes anonymous)
        triggerUserIdChange(userId: nil, useSse: true)
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Verify: Connection stopped
        XCTAssertEqual(sseConnectionManagerMock.startConnectionCallsCount, 1)
        XCTAssertEqual(sseConnectionManagerMock.stopConnectionCallsCount, 1)
    }

    func test_backgroundNotification_givenAnonymousUser_expectStopConnectionCalledAnyway() async {
        // Setup: SSE enabled but user is anonymous
        setupDefaultState(useSse: true, userId: nil)
        sut = createLifecycleManager()
        await sut.start()
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Action: Go to background
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try? await Task.sleep(nanoseconds: 100000000) // 0.1 seconds

        // Assert: stopConnection is always called when backgrounding (matching Android behavior)
        // stopConnection() is idempotent, safe to call even if SSE was never started
        XCTAssertTrue(sseConnectionManagerMock.stopConnectionCalled)
        XCTAssertEqual(sseConnectionManagerMock.stopConnectionCallsCount, 1)
    }
}
