import CioInternalCommon
import Foundation
import UIKit

// sourcery: InjectRegisterShared = "Gist"
// sourcery: InjectSingleton
public class Gist {
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
        if let subscriber = inAppMessageStoreSubscriber {
            inAppMessageManager.unsubscribe(subscriber: subscriber)
        }
        inAppMessageStoreSubscriber = nil
        queueTimer?.invalidate()
    }

    private func subscribeToInAppMessageState() {
        inAppMessageStoreSubscriber = InAppMessageStoreSubscriber { [weak self] state in
            guard let self else { return }

            let newPollingInterval = state.pollInterval
            self.setupPollingAndFetch(skipMessageFetch: true, pollingInterval: newPollingInterval)
        }
        if let subscriber = inAppMessageStoreSubscriber {
            inAppMessageManager.subscribe(keyPath: \.pollInterval, subscriber: subscriber)
        }
    }

    func resetState() {
        inAppMessageManager.dispatch(action: .resetState)
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

    private func setupPollingAndFetch(skipMessageFetch: Bool, pollingInterval: Double) {
        queueTimer?.invalidate()
        queueTimer = nil

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

    @objc
    func fetchUserMessages() {
        logger.info("fetchUserMessages called")
        guard UIApplication.shared.applicationState != .background else {
            logger.info("Application in background, skipping queue check.")
            return
        }

        logger.info("Checking Gist queue service")
        inAppMessageManager.fetchState { [weak self] state in
            guard let self else { return }

            fetchUserQueue(state: state)
        }
    }

    private func fetchUserQueue(state: InAppMessageState) {
        guard let _ = state.userId else {
            logger.debug("User token not set, skipping fetch user queue.")
            return
        }

        threadUtil.runBackground {
            self.queueManager.fetchUserQueue(state: state) { [weak self] response in
                guard let self else { return }

                switch response {
                case .success(nil):
                    logger.info("No changes to remote queue")
                    inAppMessageManager.dispatch(action: .clearMessageQueue)

                case .success(let responses):
                    guard let responses else { return }

                    logger.info("Gist queue service found \(responses.count) new messages")
                    inAppMessageManager.dispatch(action: .processMessageQueue(messages: responses.map { $0.toMessage() }))

                case .failure(let error):
                    logger.error("Error fetching messages from Gist queue service. \(error.localizedDescription)")
                    inAppMessageManager.dispatch(action: .clearMessageQueue)
                }
            }
        }
    }
}
