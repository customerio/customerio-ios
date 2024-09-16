import CioInternalCommon
import Foundation
import UIKit

// wrapper around Gist SDK to make it mockable
protocol GistProvider: AutoMockable {
    func setUserToken(_ userToken: String)
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

    private var inAppMessageStoreSubscriber: InAppMessageStoreSubscriber?
    private var queueTimer: Timer?

    init(
        logger: Logger,
        gistDelegate: GistDelegate,
        inAppMessageManager: InAppMessageManager,
        queueManager: QueueManager,
        threadUtil: ThreadUtil
    ) {
        self.logger = logger
        self.gistDelegate = gistDelegate
        self.inAppMessageManager = inAppMessageManager
        self.queueManager = queueManager
        self.threadUtil = threadUtil

        subscribeToInAppMessageState()
    }

    deinit {
        // Unsubscribe from in-app message state changes and release resources to stop polling
        // and prevent memory leaks.
        if let subscriber = inAppMessageStoreSubscriber {
            inAppMessageManager.unsubscribe(subscriber: subscriber)
        }
        inAppMessageStoreSubscriber = nil
        invalidateTimer()
    }

    private func subscribeToInAppMessageState() {
        // Keep a strong reference to the subscriber to prevent deallocation and continue receiving updates
        inAppMessageStoreSubscriber = {
            let subscriber = InAppMessageStoreSubscriber { state in
                self.setupPollingAndFetch(skipMessageFetch: true, pollingInterval: state.pollInterval)
            }
            // Subscribe to changes in `pollInterval` property of `InAppMessageState`
            inAppMessageManager.subscribe(keyPath: \.pollInterval, subscriber: subscriber)
            return subscriber
        }()
    }

    private func invalidateTimer() {
        queueTimer?.invalidate()
        queueTimer = nil
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
            guard case .displayed(let message) = state.currentMessageState else {
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
        logger.logWithModuleTag("Setting up polling with interval: \(pollingInterval) seconds and skipMessageFetch: \(skipMessageFetch)", level: .info)
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
        }

        if !skipMessageFetch {
            threadUtil.runMain {
                self.fetchUserMessages()
            }
        }
    }

    /// Fetches the user messages from the remote service and dispatches actions to the `InAppMessageManager`.
    /// The method must be marked with `@objc` and public to be used as a selector in the `Timer` scheduled.
    /// Also, the method must be called on main thread since it checks the application state.
    @objc
    func fetchUserMessages() {
        logger.logWithModuleTag("Attempting to fetch user messages from remote service", level: .info)
        guard UIApplication.shared.applicationState != .background else {
            logger.logWithModuleTag("Application in background, skipping queue check.", level: .info)
            return
        }

        logger.logWithModuleTag("Checking Gist queue service", level: .info)
        inAppMessageManager.fetchState { [weak self] state in
            guard let self else { return }

            fetchUserQueue(state: state)
        }
    }

    private func fetchUserQueue(state: InAppMessageState) {
        guard let _ = state.userId else {
            logger.logWithModuleTag("User token not set, skipping fetch user queue.", level: .debug)
            return
        }

        threadUtil.runBackground {
            self.queueManager.fetchUserQueue(state: state) { [weak self] response in
                guard let self else { return }

                switch response {
                case .success(nil):
                    logger.logWithModuleTag("No changes to remote queue", level: .info)
                    inAppMessageManager.dispatch(action: .clearMessageQueue)

                case .success(let responses):
                    guard let responses else { return }

                    logger.logWithModuleTag("Gist queue service found \(responses.count) new messages", level: .info)
                    inAppMessageManager.dispatch(action: .processMessageQueue(messages: responses.map { $0.toMessage() }))

                case .failure(let error):
                    logger.logWithModuleTag("Error fetching messages from Gist queue service. \(error.localizedDescription)", level: .error)
                    inAppMessageManager.dispatch(action: .clearMessageQueue)
                }
            }
        }
    }
}
