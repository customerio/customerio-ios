import CioInternalCommon
import Foundation
import UIKit

/// Manages the lifecycle-aware SSE connection for in-app messaging.
///
/// This class encapsulates all logic for starting/stopping SSE connections based on:
/// - App foreground/background state
/// - SSE enabled flag from server
///
/// Corresponds to Android's `SseLifecycleManager` class.
protocol SseLifecycleManager: AutoMockable {
    /// Starts the lifecycle manager. Must be called after initialization.
    /// Sets up notification observers and subscribes to SSE flag changes.
    func start() async
}

// sourcery: InjectRegisterShared = "SseLifecycleManager"
// sourcery: InjectSingleton
actor CioSseLifecycleManager: SseLifecycleManager {
    private let logger: Logger
    private let inAppMessageManager: InAppMessageManager
    private let sseConnectionManager: SseConnectionManagerProtocol

    private var notificationObservers: [NSObjectProtocol] = []
    private var sseFlagSubscriber: InAppMessageStoreSubscriber?

    private var isForegrounded: Bool = false

    init(
        logger: Logger,
        inAppMessageManager: InAppMessageManager,
        sseConnectionManager: SseConnectionManagerProtocol
    ) {
        self.logger = logger
        self.inAppMessageManager = inAppMessageManager
        self.sseConnectionManager = sseConnectionManager
    }

    /// Sets up the lifecycle manager. Must be called after initialization.
    /// This is separate from init because actors cannot call async methods in init.
    func start() async {
        logger.logWithModuleTag("SseLifecycleManager: Starting lifecycle manager", level: .debug)
        await setupInitialState()
        await setupNotificationObservers()
        subscribeToSseFlagChanges()
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
        // Get current app state on main thread
        let isForeground = await MainActor.run {
            UIApplication.shared.applicationState != .background
        }

        isForegrounded = isForeground
        logger.logWithModuleTag("SseLifecycleManager: Initial state - isForegrounded: \(isForeground)", level: .debug)

        // If already foregrounded at init time, check if we should start SSE
        if isForeground {
            await startSseIfEnabled()
        }
    }

    /// Starts SSE connection if SSE is enabled. Used for initial setup.
    private func startSseIfEnabled() async {
        let state = await inAppMessageManager.state
        if state.useSse {
            logger.logWithModuleTag("SseLifecycleManager: SSE enabled at startup - starting connection", level: .info)
            await sseConnectionManager.startConnection()
        } else {
            logger.logWithModuleTag("SseLifecycleManager: SSE disabled at startup - no action needed", level: .debug)
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
                    await self.handleSseFlagChange(sseEnabled: state.useSse)
                }
            }
            // Subscribe to changes in `useSse` property of `InAppMessageState`
            inAppMessageManager.subscribe(keyPath: \.useSse, subscriber: subscriber)
            logger.logWithModuleTag("SseLifecycleManager: Subscribed to SSE flag changes", level: .debug)
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

        let state = await inAppMessageManager.state
        if state.useSse {
            logger.logWithModuleTag("SseLifecycleManager: App foregrounded, SSE enabled - starting connection", level: .info)
            await sseConnectionManager.startConnection()
        } else {
            logger.logWithModuleTag("SseLifecycleManager: App foregrounded, SSE disabled - no action needed", level: .debug)
        }
    }

    private func handleBackgrounded() async {
        // Use compare-and-set pattern to avoid duplicate handling
        guard isForegrounded else {
            logger.logWithModuleTag("SseLifecycleManager: Already backgrounded, skipping", level: .debug)
            return
        }

        isForegrounded = false

        let state = await inAppMessageManager.state
        if state.useSse {
            logger.logWithModuleTag("SseLifecycleManager: App backgrounded, SSE enabled - stopping connection", level: .info)
            await sseConnectionManager.stopConnection()
        } else {
            logger.logWithModuleTag("SseLifecycleManager: App backgrounded, SSE disabled - no action needed", level: .debug)
        }
    }

    private func handleSseFlagChange(sseEnabled: Bool) async {
        logger.logWithModuleTag("SseLifecycleManager: SSE flag changed to \(sseEnabled)", level: .info)

        // Only act on flag changes if app is foregrounded
        guard isForegrounded else {
            logger.logWithModuleTag("SseLifecycleManager: App backgrounded, deferring SSE action until foreground", level: .debug)
            return
        }

        if sseEnabled {
            logger.logWithModuleTag("SseLifecycleManager: SSE enabled while foregrounded - starting connection", level: .info)
            await sseConnectionManager.startConnection()
        } else {
            logger.logWithModuleTag("SseLifecycleManager: SSE disabled while foregrounded - stopping connection", level: .info)
            await sseConnectionManager.stopConnection()
        }
    }
}
