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

    func fetchUserMessagesFromLocalStore() {
        Logger.instance.info(message: "Checking local store with \(localMessageStore.count) messages")
        localMessageStore.map(\.value).sortByMessagePriority().forEach { message in
            handleMessage(message: message)
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

    func addMessageToLocalStore(message: Message) {
        guard let queueId = message.queueId else {
            return
        }
        localMessageStore.updateValue(message, forKey: queueId)
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
        // To prevent us from showing expired / revoked messages, clear user messages from local queue.
        clearUserMessagesFromLocalStore()
        Logger.instance.info(message: "Gist queue service found \(fetchedMessages.count) new messages")
        for message in fetchedMessages {
            handleMessage(message: message)
        }
    }

    private func handleMessage(message: Message) {
        if message.isInlineMessage {
            // Inline Views show inline messages by getting messages stored in the local queue on device.
            // So, add the message to the local store and when inline Views are constructed, they will check the store.
            addMessageToLocalStore(message: message)

            return
        }

        // Rest of logic of function is for Modal messages

        // Skip showing Modal messages if already shown.
        if let queueId = message.queueId, Gist.shared.shownModalMessageQueueIds.contains(queueId) {
            Logger.instance.info(message: "Message with queueId: \(queueId) already shown, skipping.")
            return
        }

        let position = message.gistProperties.position

        if let routeRule = message.gistProperties.routeRule {
            let cleanRouteRule = routeRule.replacingOccurrences(of: "\\", with: "/")
            if let regex = try? NSRegularExpression(pattern: cleanRouteRule) {
                let range = NSRange(location: 0, length: Gist.shared.getCurrentRoute().utf16.count)
                if regex.firstMatch(in: Gist.shared.getCurrentRoute(), options: [], range: range) == nil {
                    Logger.instance.debug(message: "Current route is \(Gist.shared.getCurrentRoute()), needed \(cleanRouteRule)")
                    addMessageToLocalStore(message: message)
                    return
                }
            } else {
                Logger.instance.info(message: "Problem processing route rule message regex: \(cleanRouteRule)")
                return
            }
        }

        _ = gist.showMessage(message, position: position)
    }
}
