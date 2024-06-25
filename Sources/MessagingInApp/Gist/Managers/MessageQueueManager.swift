import CioInternalCommon
import Foundation
import UIKit

protocol MessageQueueManager: AutoMockable {
    func getInterval() -> Double
    func setInterval(_ newInterval: Double)
    func setup(skipQueueCheck: Bool)
    func fetchUserMessagesFromLocalStore()
    func removeMessageFromLocalStore(message: Message)
    func clearUserMessagesFromLocalStore()
    func getInlineMessages(forElementId elementId: String) -> [Message]
}

// sourcery: InjectRegisterShared = "MessageQueueManager"
// sourcery: InjectSingleton
class MessageQueueManagerImpl: MessageQueueManager {
    @Atomic private var interval: Double = 600
    private var queueTimer: Timer?

    // The local message store is used to keep messages that can't be displayed because the route rule doesnt match and inline messages.
    @Atomic var localMessageStore: [String: Message] = [:]

    private var gist: GistInstance {
        DIGraphShared.shared.gist
    }

    private var eventBus: EventBusHandler {
        DIGraphShared.shared.eventBusHandler
    }

    func getInterval() -> Double {
        interval
    }

    func setInterval(_ newInterval: Double) {
        interval = newInterval
    }

    func setup(skipQueueCheck: Bool) {
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

    deinit {
        queueTimer?.invalidate()
    }

    func fetchUserMessagesFromLocalStore() {
        Logger.instance.info(message: "Checking local store with \(localMessageStore.count) messages")
        localMessageStore.map(\.value).sortByMessagePriority().forEach { message in
            showMessageIfMeetsCriteria(message: message)
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

    func getInlineMessages(forElementId elementId: String) -> [Message] {
        localMessageStore.filter { $0.value.elementId == elementId }.map(\.value).sortByMessagePriority()
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
    private func fetchUserMessages() {
        if UIApplication.shared.applicationState != .background {
            Logger.instance.info(message: "Checking Gist queue service")
            if let userToken = UserManager().getUserToken() {
                QueueManager(siteId: Gist.shared.siteId, dataCenter: Gist.shared.dataCenter)
                    .fetchUserQueue(userToken: userToken, completionHandler: { response in
                        switch response {
                        case .success(nil):
                            Logger.instance.info(message: "No changes to remote queue")
                        case .success(let responses):
                            guard let responses else {
                                return
                            }

                            self.processFetchedMessages(responses.map { $0.toMessage() })
                        case .failure(let error):
                            Logger.instance.error(message: "Error fetching messages from Gist queue service. \(error.localizedDescription)")
                        }
                    })
            } else {
                Logger.instance.debug(message: "User token not set, skipping fetch user queue.")
            }
        } else {
            Logger.instance.info(message: "Application in background, skipping queue check.")
        }
    }

    func processFetchedMessages(_ fetchedMessages: [Message]) {
        // To prevent us from showing expired / revoked messages, reset the local queue with the latest queue from the backend service.
        // The backend service is the single-source-of-truth for in-app messages for each user.
        clearUserMessagesFromLocalStore()
        addMessagesToLocalStore(messages: fetchedMessages)
        Logger.instance.info(message: "Gist queue service found \(fetchedMessages.count) new messages")

        for message in fetchedMessages {
            showMessageIfMeetsCriteria(message: message)
        }

        // Notify observers that a fetch has completed and the local queue has been modified.
        // This is useful for inline Views that may need to display or dismiss messages.
        eventBus.postEvent(InAppMessagesFetchedEvent())
    }

    private func showMessageIfMeetsCriteria(message: Message) {
        if message.isInlineMessage {
            // Inline Views show inline messages by getting messages stored in the local queue on device.
            return
        }

        // Rest of logic of function is for Modal messages

        // Skip showing Modal messages if already shown.
        if let queueId = message.queueId, Gist.shared.shownModalMessageQueueIds.contains(queueId) {
            Logger.instance.info(message: "Message with queueId: \(queueId) already shown, skipping.")
            return
        }

        let position = message.gistProperties.position

        if message.doesHavePageRule(), let cleanPageRule = message.cleanPageRule {
            if !message.doesPageRuleMatch(route: Gist.shared.getCurrentRoute()) {
                Logger.instance.debug(message: "Current route is \(Gist.shared.getCurrentRoute()), needed \(cleanPageRule)")
                return // exit early to not show the message since page rule doesnt match
            }
        }

        _ = gist.showMessage(message, position: position)
    }
}
