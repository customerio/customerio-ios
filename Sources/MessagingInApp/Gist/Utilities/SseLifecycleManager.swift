import CioInternalCommon
import Foundation
import UIKit

/// Manages the lifecycle-aware SSE connection for in-app messaging.
///
/// This class encapsulates all logic for starting/stopping SSE connections based on:
/// - App foreground/background state
/// - SSE enabled flag from server
/// - User identification state (userId is set)
///
/// SSE requires ALL three conditions to be met:
/// 1. App is foregrounded
/// 2. SSE flag is enabled (from X-CIO-Use-SSE header)
/// 3. User is identified (userId is set, not anonymous)
///
/// Otherwise, the SDK falls back to polling.
///
/// Corresponds to Android's `SseLifecycleManager` class.
protocol SseLifecycleManager: AutoMockable {
    /// Starts the lifecycle manager. Must be called after initialization.
    /// Sets up notification observers and subscribes to SSE flag and userId changes.
    func start() async
}

// sourcery: InjectRegisterShared = "SseLifecycleManager"
// sourcery: InjectSingleton
actor CioSseLifecycleManager: SseLifecycleManager {
    private let logger: Logger
    private let inAppMessageManager: InAppMessageManager
    private let sseConnectionManager: SseConnectionManagerProtocol
    private let applicationStateProvider: ApplicationStateProvider

    private var notificationObservers: [NSObjectProtocol] = []
    private var sseFlagSubscriber: InAppMessageStoreSubscriber?
    private var userIdSubscriber: InAppMessageStoreSubscriber?

    private var isForegrounded: Bool = false

    init(
        logger: Logger,
        inAppMessageManager: InAppMessageManager,
        sseConnectionManager: SseConnectionManagerProtocol,
        applicationStateProvider: ApplicationStateProvider
    ) {
        self.logger = logger
        self.inAppMessageManager = inAppMessageManager
        self.sseConnectionManager = sseConnectionManager
        self.applicationStateProvider = applicationStateProvider
    }

    /// Sets up the lifecycle manager. Must be called after initialization.
    /// This is separate from init because actors cannot call async methods in init.
    ///
    /// The order of operations is important to avoid race conditions:
    /// 1. Register notification observers first to catch any state transitions
    /// 2. Subscribe to SSE flag changes
    /// 3. Check initial state last - any transitions during setup will be caught by observers
    func start() async {
        logger.logWithModuleTag("SseLifecycleManager: Starting lifecycle manager", level: .debug)

        // Register observers FIRST to ensure no state transitions are missed
        await setupNotificationObservers()
        subscribeToSseFlagChanges()
        subscribeToUserIdChanges()

        // Check initial state LAST - if app went to background during setup,
        // we'll either see it here or have already received the notification
        await setupInitialState()

        logger.logWithModuleTag("SseLifecycleManager: Lifecycle manager started successfully", level: .info)
    }

    deinit {
        // Remove notification observers
        let notificationCenter = NotificationCenter.default
        for observer in notificationObservers {
            notificationCenter.removeObserver(observer)
        }

        // Note: Cannot unsubscribe from inAppMessageManager here as deinit cannot be async
        // The subscriber uses weak reference so it will be cleaned up automatically
    }

    // MARK: - Setup

    private func setupInitialState() async {
        // Get current app state using injected provider for testability
        let isForeground = await MainActor.run {
            applicationStateProvider.applicationState != .background
        }

        isForegrounded = isForeground

        // Get current state for logging and initial SSE state check
        let state = await inAppMessageManager.state

        logger.logWithModuleTag(
            "SseLifecycleManager: Initial state - isForegrounded: \(isForeground), sseEnabled: \(state.useSse), isUserIdentified: \(state.isUserIdentified), userId: \(state.userId ?? "nil")",
            level: .info
        )

        // If already foregrounded at init time, check if we should start SSE
        if isForeground {
            logger.logWithModuleTag("SseLifecycleManager: App already foregrounded at init - checking SSE eligibility", level: .debug)
            await startSseIfEligible(state: state)
        } else {
            logger.logWithModuleTag("SseLifecycleManager: App backgrounded at init - SSE will start when foregrounded", level: .debug)
        }
    }

    // MARK: - SSE Eligibility

    /// Starts SSE connection if all eligibility conditions are met.
    /// Uses the provided state to check: sseEnabled && isUserIdentified
    private func startSseIfEligible(state: InAppMessageState) async {
        logger.logWithModuleTag(
            "SseLifecycleManager: Checking SSE eligibility - sseEnabled: \(state.useSse), isUserIdentified: \(state.isUserIdentified)",
            level: .debug
        )

        if state.shouldUseSse {
            logger.logWithModuleTag("SseLifecycleManager: All conditions met - starting SSE connection", level: .info)
            await sseConnectionManager.startConnection()
        } else {
            logger.logWithModuleTag(
                "SseLifecycleManager: SSE conditions not met (sseEnabled: \(state.useSse), isUserIdentified: \(state.isUserIdentified)) - using polling",
                level: .debug
            )
        }
    }

    private func setupNotificationObservers() async {
        let notificationCenter = NotificationCenter.default

        // Observe when app enters foreground
        let foregroundObserver = notificationCenter.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.handleForegrounded()
            }
        }
        notificationObservers.append(foregroundObserver)

        // Observe when app enters background
        let backgroundObserver = notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.handleBackgrounded()
            }
        }
        notificationObservers.append(backgroundObserver)

        logger.logWithModuleTag("SseLifecycleManager: Notification observers registered", level: .debug)
    }

    private func subscribeToSseFlagChanges() {
        sseFlagSubscriber = {
            let subscriber = InAppMessageStoreSubscriber { [weak self] state in
                guard let self else { return }
                Task {
                    await self.handleSseFlagChange(state: state)
                }
            }
            // Subscribe to changes in `useSse` property of `InAppMessageState`
            inAppMessageManager.subscribe(keyPath: \.useSse, subscriber: subscriber)
            logger.logWithModuleTag("SseLifecycleManager: Subscribed to SSE flag changes", level: .debug)
            return subscriber
        }()
    }

    private func subscribeToUserIdChanges() {
        userIdSubscriber = {
            let subscriber = InAppMessageStoreSubscriber { [weak self] state in
                guard let self else { return }
                Task {
                    await self.handleUserIdChange(state: state)
                }
            }
            // Subscribe to changes in `userId` property of `InAppMessageState`
            inAppMessageManager.subscribe(keyPath: \.userId, subscriber: subscriber)
            logger.logWithModuleTag("SseLifecycleManager: Subscribed to userId changes", level: .debug)
            return subscriber
        }()
    }

    // MARK: - Lifecycle Handlers

    private func handleForegrounded() async {
        // Use compare-and-set pattern to avoid duplicate handling
        guard !isForegrounded else {
            logger.logWithModuleTag("SseLifecycleManager: Already foregrounded, skipping", level: .debug)
            return
        }

        isForegrounded = true

        // Get current state (like Android's getCurrentState())
        let state = await inAppMessageManager.state

        logger.logWithModuleTag(
            "SseLifecycleManager: App foregrounded - checking SSE eligibility (sseEnabled: \(state.useSse), isUserIdentified: \(state.isUserIdentified))",
            level: .info
        )

        // Check all 3 conditions: foregrounded + SSE enabled + user identified
        await startSseIfEligible(state: state)
    }

    private func handleBackgrounded() async {
        // Use compare-and-set pattern to avoid duplicate handling
        guard isForegrounded else {
            logger.logWithModuleTag("SseLifecycleManager: Already backgrounded, skipping", level: .debug)
            return
        }

        isForegrounded = false

        // Always stop SSE connection when app backgrounds (matching Android behavior)
        // stopConnection() is idempotent, safe to call even if not connected
        logger.logWithModuleTag("SseLifecycleManager: App backgrounded - stopping SSE connection", level: .info)
        await sseConnectionManager.stopConnection()
    }

    private func handleSseFlagChange(state _: InAppMessageState) async {
        // Always fetch latest state to handle out-of-order Task execution
        // This prevents race conditions when state changes rapidly (e.g., SSE enabled → disabled)
        let state = await inAppMessageManager.state

        logger.logWithModuleTag(
            "SseLifecycleManager: SSE flag changed to \(state.useSse) (isUserIdentified: \(state.isUserIdentified), isForegrounded: \(isForegrounded))",
            level: .info
        )

        // Only act on flag changes if app is foregrounded
        guard isForegrounded else {
            logger.logWithModuleTag(
                "SseLifecycleManager: App backgrounded - deferring SSE action until foreground",
                level: .debug
            )
            return
        }

        // Check if SSE should be used (matching Android's state.shouldUseSse check)
        if state.shouldUseSse {
            logger.logWithModuleTag("SseLifecycleManager: SSE enabled + user identified - starting SSE connection", level: .info)
            await sseConnectionManager.startConnection()
        } else if state.useSse, !state.isUserIdentified {
            // SSE enabled but user is anonymous - don't start SSE
            logger.logWithModuleTag("SseLifecycleManager: SSE enabled but user anonymous - SSE will not be used, polling continues", level: .info)
        } else if !state.useSse {
            // SSE disabled → Stop SSE connection (idempotent, safe to call even if not connected)
            logger.logWithModuleTag("SseLifecycleManager: SSE disabled - stopping SSE connection, falling back to polling", level: .info)
            await sseConnectionManager.stopConnection()
        }
    }

    private func handleUserIdChange(state _: InAppMessageState) async {
        // Always fetch latest state to handle out-of-order Task execution
        // This prevents race conditions when userId changes rapidly (e.g., login → logout)
        let state = await inAppMessageManager.state

        logger.logWithModuleTag(
            "SseLifecycleManager: User identification changed to \(state.isUserIdentified) (sseEnabled: \(state.useSse), isForegrounded: \(isForegrounded))",
            level: .info
        )

        // Only act on identification changes if app is foregrounded
        guard isForegrounded else {
            logger.logWithModuleTag(
                "SseLifecycleManager: App backgrounded - deferring user identification action until foreground",
                level: .debug
            )
            return
        }

        // Check if SSE should be used (matching Android's state.shouldUseSse check)
        if state.shouldUseSse {
            // User became identified and SSE is enabled - start SSE connection
            logger.logWithModuleTag("SseLifecycleManager: User identified + SSE enabled - starting SSE connection", level: .info)
            await sseConnectionManager.startConnection()
        } else if !state.isUserIdentified, state.useSse {
            // User became anonymous and SSE flag is enabled - stop SSE, fall back to polling
            logger.logWithModuleTag("SseLifecycleManager: User became anonymous - stopping SSE, falling back to polling", level: .info)
            await sseConnectionManager.stopConnection()
        } else {
            logger.logWithModuleTag(
                "SseLifecycleManager: No SSE action needed (shouldUseSse: \(state.shouldUseSse), sseEnabled: \(state.useSse), isUserIdentified: \(state.isUserIdentified))",
                level: .debug
            )
        }
    }
}
