import CioInternalCommon
import Foundation
import UIKit

// wrapper around Gist SDK to make it mockable
protocol GistProvider: AutoMockable {
    func setUserToken(_ userToken: String)
    func setAnonymousId(_ anonymousId: String)
    func setCurrentRoute(_ currentRoute: String)
    func fetchUserMessagesFromRemoteQueue()
    func resetState()
    func setEventListener(_ eventListener: InAppEventListener?)
    func dismissMessage()
}

// sourcery: InjectRegisterShared = "GistProvider"
// sourcery: InjectSingleton
/// Main class that is responsible for managing in-app message queue from remote service and
/// dispatching actions to `InAppMessageManager` based on user and route changes.
/// This class is also responsible for scheduling polling of in-app message queue based on
/// `InAppMessageState.pollInterval`.
class Gist: GistProvider {
    private let logger: Logger
    private let gistDelegate: GistDelegate
    private let inAppMessageManager: InAppMessageManager
    private let queueManager: QueueManager
    private let threadUtil: ThreadUtil
    private let sseLifecycleManager: SseLifecycleManager

    private var pollIntervalSubscriber: InAppMessageStoreSubscriber?
    private var sseEnabledSubscriber: InAppMessageStoreSubscriber?
    private var userIdSubscriber: InAppMessageStoreSubscriber?
    private var queueTimer: Timer?

    // Lifecycle observers for pausing/resuming polling timer
    private var foregroundObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?

    init(
        logger: Logger,
        gistDelegate: GistDelegate,
        inAppMessageManager: InAppMessageManager,
        queueManager: QueueManager,
        threadUtil: ThreadUtil,
        sseLifecycleManager: SseLifecycleManager
    ) {
        self.logger = logger
        self.gistDelegate = gistDelegate
        self.inAppMessageManager = inAppMessageManager
        self.queueManager = queueManager
        self.threadUtil = threadUtil
        self.sseLifecycleManager = sseLifecycleManager

        subscribeToInAppMessageState()
        setupLifecycleObservers()

        // Start the SSE lifecycle manager to observe app foreground/background events
        Task {
            await sseLifecycleManager.start()
        }
    }

    deinit {
        // Unsubscribe from in-app message state changes and release resources to stop polling
        // and prevent memory leaks.
        if let subscriber = pollIntervalSubscriber {
            inAppMessageManager.unsubscribe(subscriber: subscriber)
        }
        if let subscriber = sseEnabledSubscriber {
            inAppMessageManager.unsubscribe(subscriber: subscriber)
        }
        if let subscriber = userIdSubscriber {
            inAppMessageManager.unsubscribe(subscriber: subscriber)
        }
        pollIntervalSubscriber = nil
        sseEnabledSubscriber = nil
        userIdSubscriber = nil

        // Remove lifecycle observers
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        invalidateTimer()
    }

    private func subscribeToInAppMessageState() {
        // Subscribe to poll interval changes
        pollIntervalSubscriber = {
            let subscriber = InAppMessageStoreSubscriber { [weak self] state in
                guard let self else { return }
                // Only update polling if SSE is not active
                if !state.shouldUseSse {
                    setupPollingAndFetch(skipMessageFetch: true, pollingInterval: state.pollInterval)
                }
            }
            inAppMessageManager.subscribe(keyPath: \.pollInterval, subscriber: subscriber)
            return subscriber
        }()

        // Subscribe to SSE flag changes (matching Android's subscribeToAttribute for sseEnabled)
        sseEnabledSubscriber = {
            let subscriber = InAppMessageStoreSubscriber { [weak self] state in
                guard let self else { return }
                handleSseEnabledChange(state: state)
            }
            inAppMessageManager.subscribe(keyPath: \.useSse, subscriber: subscriber)
            logger.logWithModuleTag("Gist: Subscribed to SSE flag changes", level: .debug)
            return subscriber
        }()

        // Subscribe to user identification changes (matching Android's subscribeToAttribute for isUserIdentified)
        userIdSubscriber = {
            let subscriber = InAppMessageStoreSubscriber { [weak self] state in
                guard let self else { return }
                handleUserIdentificationChange(state: state)
            }
            inAppMessageManager.subscribe(keyPath: \.userId, subscriber: subscriber)
            logger.logWithModuleTag("Gist: Subscribed to userId changes", level: .debug)
            return subscriber
        }()
    }

    fileprivate func invalidateTimer() {
        // Timer must be scheduled or modified on main.
        threadUtil.runMain {
            self.queueTimer?.invalidate()
            self.queueTimer = nil
        }
    }

    func resetState() {
        inAppMessageManager.dispatch(action: .resetState)
        queueManager.clearCachedUserQueue()
        invalidateTimer()
    }

    func setEventListener(_ eventListener: InAppEventListener?) {
        gistDelegate.setEventListener(eventListener)
    }

    func dismissMessage() {
        inAppMessageManager.fetchState { [self] state in
            guard case .displayed(let message) = state.modalMessageState else {
                return
            }

            inAppMessageManager.dispatch(action: .dismissMessage(message: message))
        }
    }

    // MARK: User Token and Route

    func setUserToken(_ userToken: String) {
        inAppMessageManager.fetchState { [self] state in
            if state.userId == userToken {
                return
            }

            inAppMessageManager.dispatch(action: .setUserIdentifier(user: userToken))
            setupPollingAndFetch(skipMessageFetch: false, pollingInterval: state.pollInterval)
        }
    }

    func setAnonymousId(_ anonymousId: String) {
        inAppMessageManager.fetchState { [self] state in
            if state.anonymousId == anonymousId {
                return
            }

            inAppMessageManager.dispatch(action: .setAnonymousIdentifier(anonymousId: anonymousId))
            setupPollingAndFetch(skipMessageFetch: false, pollingInterval: state.pollInterval)
        }
    }

    func setCurrentRoute(_ currentRoute: String) {
        inAppMessageManager.fetchState { [self] state in
            if state.currentRoute == currentRoute {
                return // ignore request, route has not changed.
            }

            inAppMessageManager.dispatch(action: .setPageRoute(route: currentRoute))
        }
    }

    // MARK: Message Queue Polling

    func fetchUserMessagesFromRemoteQueue() {
        logger.logWithModuleTag("Requesting to fetch user messages from remote service", level: .info)
        inAppMessageManager.fetchState { [weak self] state in
            guard let self else { return }

            setupPollingAndFetch(skipMessageFetch: false, pollingInterval: state.pollInterval)
        }
    }

    private func setupPollingAndFetch(skipMessageFetch: Bool, pollingInterval: Double) {
        logger.logWithModuleTag("Gist: Setting up polling timer - interval: \(pollingInterval)s, skipInitialFetch: \(skipMessageFetch)", level: .info)
        invalidateTimer()

        // Timer must be scheduled on the main thread
        threadUtil.runMain {
            self.queueTimer = Timer.scheduledTimer(
                timeInterval: pollingInterval,
                target: self,
                selector: #selector(self.fetchUserMessages),
                userInfo: nil,
                repeats: true
            )
            self.logger.logWithModuleTag("Gist: Polling timer started with interval: \(pollingInterval)s", level: .debug)
        }

        if !skipMessageFetch {
            threadUtil.runMain {
                self.fetchUserMessages()
            }
        }
    }

    /// Fetches the user messages from the remote service and dispatches actions to the `InAppMessageManager`.
    /// The method must be marked with `@objc` to be used as a selector in the `Timer` scheduled.
    @objc
    func fetchUserMessages() {
        inAppMessageManager.fetchState { [weak self] state in
            guard let self else { return }

            // Skip polling only if SSE should be used (enabled + user is identified)
            // Anonymous users always use polling even if SSE flag is enabled
            guard !state.shouldUseSse else {
                logger.logWithModuleTag(
                    "Gist: Skipping polling - SSE active (sseEnabled: \(state.useSse), isUserIdentified: \(state.isUserIdentified))",
                    level: .debug
                )
                return
            }

            logger.logWithModuleTag(
                "Gist: Polling for messages (sseEnabled: \(state.useSse), isUserIdentified: \(state.isUserIdentified))",
                level: .info
            )
            fetchUserQueue(state: state)
        }
    }

    private func fetchUserQueue(state: InAppMessageState) {
        // Allow fetching with either userId or anonymousId
        guard state.userId != nil || state.anonymousId != nil else {
            logger.logWithModuleTag("Neither user token nor anonymous ID set, skipping fetch user queue.", level: .debug)
            return
        }

        threadUtil.runBackground {
            self.queueManager.fetchUserQueue(state: state) { [weak self] response in
                guard let self else { return }

                switch response {
                case .success(nil):
                    logger.logWithModuleTag("No changes to remote queue", level: .info)
                    inAppMessageManager.dispatch(action: .clearMessageQueue)

                case .success(let messages):
                    guard let messages else { return }

                    logger.logWithModuleTag("Gist queue service found \(messages.count) new messages", level: .info)
                    inAppMessageManager.dispatch(action: .processMessageQueue(messages: messages))

                case .failure(let error):
                    logger.logWithModuleTag("Error fetching messages from Gist queue service. \(error.localizedDescription)", level: .error)
                    inAppMessageManager.dispatch(action: .clearMessageQueue)
                }
            }
        }
    }
}

// MARK: - App Lifecycle & SSE State Handling

private extension Gist {
    func setupLifecycleObservers() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleForegrounded()
        }

        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleBackgrounded()
        }
    }

    private func handleForegrounded() {
        logger.logWithModuleTag("Gist: App foregrounded - resuming polling timer", level: .info)

        inAppMessageManager.fetchState { [weak self] state in
            guard let self, !state.shouldUseSse else { return }
            setupPollingAndFetch(skipMessageFetch: false, pollingInterval: state.pollInterval)
        }
    }

    private func handleBackgrounded() {
        logger.logWithModuleTag("Gist: App backgrounded - pausing polling timer", level: .info)
        invalidateTimer()
    }

    /// Handles SSE flag changes for polling control.
    func handleSseEnabledChange(state: InAppMessageState) {
        if state.shouldUseSse {
            logger.logWithModuleTag("Gist: SSE enabled for identified user - stopping polling timer", level: .info)
            invalidateTimer()
        } else if !state.useSse {
            logger.logWithModuleTag("Gist: SSE disabled - starting polling with interval: \(state.pollInterval)s", level: .info)
            setupPollingAndFetch(skipMessageFetch: false, pollingInterval: state.pollInterval)
        }
    }

    /// Handles user identification changes for polling control.
    func handleUserIdentificationChange(state: InAppMessageState) {
        if state.shouldUseSse {
            logger.logWithModuleTag("Gist: User identified with SSE enabled - stopping polling (SSE will handle messages)", level: .info)
            invalidateTimer()
        } else if !state.isUserIdentified, state.useSse {
            logger.logWithModuleTag("Gist: User became anonymous with SSE enabled - starting polling", level: .info)
            setupPollingAndFetch(skipMessageFetch: false, pollingInterval: state.pollInterval)
        }
    }
}
