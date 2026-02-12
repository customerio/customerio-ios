import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "QueueManager"
// sourcery: InjectSingleton
class QueueManager {
    private var keyValueStore: SharedKeyValueStorage
    private let gistQueueNetwork: GistQueueNetwork
    private let inAppMessageManager: InAppMessageManager
    private let anonymousMessageManager: AnonymousMessageManager
    private let logger: Logger

    private var cachedFetchUserQueueResponse: Data? {
        get {
            keyValueStore.data(.inAppUserQueueFetchCachedResponse)
        }
        set {
            keyValueStore.setData(newValue, forKey: .inAppUserQueueFetchCachedResponse)
        }
    }

    init(
        keyValueStore: SharedKeyValueStorage,
        gistQueueNetwork: GistQueueNetwork,
        inAppMessageManager: InAppMessageManager,
        anonymousMessageManager: AnonymousMessageManager,
        logger: Logger
    ) {
        self.keyValueStore = keyValueStore
        self.gistQueueNetwork = gistQueueNetwork
        self.inAppMessageManager = inAppMessageManager
        self.anonymousMessageManager = anonymousMessageManager
        self.logger = logger
    }

    func clearCachedUserQueue() {
        cachedFetchUserQueueResponse = nil
    }

    func fetchUserQueue(state: InAppMessageState, completionHandler: @escaping (Result<[Message]?, Error>) -> Void) {
        do {
            try gistQueueNetwork.request(state: state, request: QueueEndpoint.getUserQueue, completionHandler: { response in
                switch response {
                case .success(let (data, response)):
                    self.updatePollingInterval(headers: response.allHeaderFields)
                    self.updateSseFlag(headers: response.allHeaderFields)
                    self.logger.logWithModuleTag("Gist queue fetch response: \(response.statusCode)", level: .debug)
                    switch response.statusCode {
                    case 304:
                        guard let lastCachedResponse = self.cachedFetchUserQueueResponse else {
                            return completionHandler(.success(nil))
                        }

                        do {
                            let userQueue = try self.parseResponseBody(lastCachedResponse)
                            let processedQueue = self.processAnonymousMessages(userQueue)

                            completionHandler(.success(processedQueue))
                        } catch {
                            completionHandler(.failure(error))
                        }
                    default:
                        do {
                            let userQueue = try self.parseResponseBody(data)

                            self.cachedFetchUserQueueResponse = data
                            let processedQueue = self.processAnonymousMessages(userQueue)

                            completionHandler(.success(processedQueue))
                        } catch {
                            completionHandler(.failure(error))
                        }
                    }
                case .failure(let error):
                    self.logger.logWithModuleTag("Gist queue fetch response failure: \(error)", level: .debug)
                    completionHandler(.failure(error))
                }
            })
        } catch {
            logger.logWithModuleTag("Gist queue fetch response error: \(error)", level: .debug)
            completionHandler(.failure(error))
        }
    }

    /// Processes anonymous messages from the server response.
    /// - Stores anonymous messages locally with expiry
    /// - Filters out server-provided anonymous messages from the queue
    /// - Retrieves eligible anonymous messages from local storage
    /// - Combines regular messages with eligible anonymous messages
    private func processAnonymousMessages(_ userQueue: [InAppMessageResponse]?) -> [Message]? {
        guard let userQueue = userQueue else {
            return nil
        }

        // Convert to Message objects and separate anonymous from regular in one pass
        let allMessages = userQueue.map { $0.toMessage() }
        let (anonymousMessages, regularMessages) = allMessages.reduce(into: ([Message](), [Message]())) { result, message in
            if message.isAnonymousMessage {
                result.0.append(message)
            } else {
                result.1.append(message)
            }
        }

        // Update local store with anonymous messages from server
        anonymousMessageManager.updateMessagesLocalStore(messages: anonymousMessages)

        // Get eligible anonymous messages from local storage
        let eligibleAnonymousMessages = anonymousMessageManager.getEligibleMessages()

        // Combine regular messages with eligible anonymous messages
        let combinedMessages = regularMessages + eligibleAnonymousMessages

        logger.logWithModuleTag(
            "Processed messages: \(regularMessages.count) regular + \(eligibleAnonymousMessages.count) eligible anonymous = \(combinedMessages.count) total",
            level: .debug
        )

        return combinedMessages
    }

    private func parseResponseBody(_ responseBody: Data) throws -> [InAppMessageResponse] {
        guard let responseObject = try JSONSerialization.jsonObject(
            with: responseBody,
            options: .allowFragments
        ) as? [String: Any?],
            let queueResponse = QueueMessagesResponse(dictionary: responseObject)
        else {
            logger.logWithModuleTag("Failed to parse queue response", level: .error)
            return []
        }

        let inboxMessages = queueResponse.inboxMessages
        let inAppMessages = queueResponse.inAppMessages
        logger.logWithModuleTag("Found \(inAppMessages.count) in-app messages, \(inboxMessages.count) inbox messages", level: .debug)

        // Process inbox messages if any are present
        if !inboxMessages.isEmpty {
            let inboxMessagesMapped = inboxMessages.compactMap { $0.toDomainModel() }
            // Dispatch action to update inbox messages in state
            inAppMessageManager.dispatch(action: .processInboxMessages(messages: inboxMessagesMapped))
        }

        // Return in-app messages for existing flow
        return inAppMessages
    }

    private func updatePollingInterval(headers: [AnyHashable: Any]) {
        guard let newPollingIntervalString = headers["x-gist-queue-polling-interval"] as? String,
              let newPollingInterval = Double(newPollingIntervalString) else { return }

        inAppMessageManager.fetchState { [weak self] state in
            guard let self = self, newPollingInterval != state.pollInterval else { return }

            logger.logWithModuleTag("Updating polling interval to: \(newPollingInterval) seconds", level: .debug)
            inAppMessageManager.dispatch(action: .setPollingInterval(interval: newPollingInterval))
        }
    }

    private func updateSseFlag(headers: [AnyHashable: Any]) {
        // Check for SSE flag in headers
        if let sseHeaderValue = headers["x-cio-use-sse"] as? String {
            logger.logWithModuleTag("X-CIO-Use-SSE header found with value: '\(sseHeaderValue)'", level: .info)
            let useSse = sseHeaderValue.lowercased() == "true"

            inAppMessageManager.fetchState { [weak self] state in
                guard let self = self else { return }

                // Only update if the value has changed
                if state.useSse != useSse {
                    logger.logWithModuleTag("SSE flag changing from \(state.useSse) to \(useSse)", level: .info)
                    inAppMessageManager.dispatch(action: .setSseEnabled(enabled: useSse))
                } else {
                    logger.logWithModuleTag("SSE flag unchanged, remains: \(useSse)", level: .debug)
                }
            }
        } else {
            logger.logWithModuleTag("X-CIO-Use-SSE header not present in response", level: .debug)
        }
    }
}
