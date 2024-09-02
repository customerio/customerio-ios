import CioInternalCommon
import Foundation
import UIKit

class MessageQueueManager {
    private let logger: Logger
    var interval: Double = 600
    private var queueTimer: Timer?
    // The local message store is used to keep messages that can't be displayed because the route rule doesnt match.
    var localMessageStore: [String: Message] = [:]

    init() {
        self.logger = DIGraphShared.shared.logger
    }

    func setup(skipQueueCheck: Bool = false) {
        queueTimer?.invalidate()
        queueTimer = nil

        queueTimer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(fetchUserMessages),
            userInfo: nil,
            repeats: true
        )

        if !skipQueueCheck {
            // Since on app launch there's a short period where the applicationState is still set to "background"
            // We wait 1 second for the app to become active before checking for messages.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.fetchUserMessages()
            }
        }
    }

    func clearLocalStore() {
        localMessageStore = [:]
        QueueManager(siteId: Gist.shared.siteId, dataCenter: Gist.shared.dataCenter).clearCachedUserQueue()
    }

    deinit {
        queueTimer?.invalidate()
    }

    func fetchUserMessagesFromLocalStore() {
        logger.info("Checking local store with \(localMessageStore.count) messages")
        let sortedMessages = localMessageStore.sorted {
            switch ($0.value.priority, $1.value.priority) {
            case (let priority0?, let priority1?):
                // Both messages have a priority, so we compare them.
                return priority0 < priority1
            case (nil, _):
                // The first message has no priority, it should be considered greater so that it ends up at the end of the sorted array.
                return false
            case (_, nil):
                // The second message has no priority, the first message should be ordered first.
                return true
            }
        }
        sortedMessages.forEach { message in
            showMessageIfMeetsCriteria(message: message.value)
        }
    }

    func clearUserMessagesFromLocalStore() {
        localMessageStore.removeAll()
    }

    func removeMessageFromLocalStore(message: Message) {
        guard let queueId = message.queueId else {
            return
        }
        localMessageStore.removeValue(forKey: queueId)
    }

    func addMessagesToLocalStore(messages: [Message]) {
        messages.forEach { message in
            guard let queueId = message.queueId else {
                return
            }
            localMessageStore.updateValue(message, forKey: queueId)
        }
    }

    @objc
    func fetchUserMessages() {
        if UIApplication.shared.applicationState != .background {
            logger.info("Checking Gist queue service")
            if let userToken = UserManager().getUserToken() {
                QueueManager(siteId: Gist.shared.siteId, dataCenter: Gist.shared.dataCenter)
                    .fetchUserQueue(userToken: userToken, completionHandler: { response in
                        switch response {
                        case .success(nil):
                            self.logger.info("No changes to remote queue")
                        case .success(let responses):
                            guard let responses else {
                                return
                            }

                            self.logger.info("Gist queue service found \(responses.count) new messages")

                            self.processFetchResponse(responses.map { $0.toMessage() })
                        case .failure(let error):
                            self.logger.error("Error fetching messages from Gist queue service. \(error.localizedDescription)")
                        }
                    })
            } else {
                logger.debug("User token not set, skipping fetch user queue.")
            }
        } else {
            logger.info("Application in background, skipping queue check.")
        }
    }

    func processFetchResponse(_ fetchedMessages: [Message]) {
        // To prevent us from showing expired / revoked messages, reset the local queue with the latest queue from the backend service.
        // The backend service is the single-source-of-truth for in-app messages for each user.
        clearUserMessagesFromLocalStore()
        addMessagesToLocalStore(messages: fetchedMessages)

        for message in fetchedMessages {
            showMessageIfMeetsCriteria(message: message)
        }
    }

    private func showMessageIfMeetsCriteria(message: Message) {
        // Skip shown messages
        if let queueId = message.queueId, Gist.shared.shownMessageQueueIds.contains(queueId) {
            logger.info("Message with queueId: \(queueId) already shown, skipping.")
            return
        }

        let position = message.gistProperties.position

        if message.doesHavePageRule(), let cleanPageRule = message.cleanPageRule {
            if !message.doesPageRuleMatch(route: Gist.shared.getCurrentRoute()) {
                logger.debug("Current route is \(Gist.shared.getCurrentRoute()), needed \(cleanPageRule)")
                return // exit early to not show the message since page rule doesnt match
            }
        }

        if let elementId = message.gistProperties.elementId {
            logger.info("Embedding message with Element Id \(elementId)")
            Gist.shared.embedMessage(message: message, elementId: elementId)
            return
        } else {
            _ = Gist.shared.showMessage(message, position: position)
        }
    }
}
