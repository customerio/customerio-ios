import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "QueueManager"
// sourcery: InjectSingleton
class QueueManager {
    private var keyValueStore: SharedKeyValueStorage
    private let gistQueueNetwork: GistQueueNetwork
    private let inAppMessageManager: InAppMessageManager
    private let anonymousMessageManager: AnonymousMessageManager
    private let inboxMessageCache: InboxMessageCacheManager
    private let visualInboxRepository: VisualInboxRepository
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
        inboxMessageCache: InboxMessageCacheManager,
        visualInboxRepository: VisualInboxRepository,
        logger: Logger
    ) {
        self.keyValueStore = keyValueStore
        self.gistQueueNetwork = gistQueueNetwork
        self.inAppMessageManager = inAppMessageManager
        self.anonymousMessageManager = anonymousMessageManager
        self.inboxMessageCache = inboxMessageCache
        self.visualInboxRepository = visualInboxRepository
        self.logger = logger
    }

    func clearCachedUserQueue() {
        cachedFetchUserQueueResponse = nil
        inboxMessageCache.clearAll()
    }

    func fetchUserQueue(state: InAppMessageState, completionHandler: @escaping (Result<[Message]?, Error>) -> Void) {
        do {
            try gistQueueNetwork.request(state: state, request: QueueEndpoint.getUserQueue, completionHandler: { response in
                switch response {
                case .success(let (data, response)):
                    self.updatePollingInterval(headers: response.allHeaderFields)
                    self.updateSseFlag(headers: response.allHeaderFields)
                    let inboxEnabledHeader = self.readInboxEnabledHeader(headers: response.allHeaderFields)
                    self.logger.logWithModuleTag("Gist queue fetch response: \(response.statusCode)", level: .debug)
                    switch response.statusCode {
                    case 304:
                        guard let lastCachedResponse = self.cachedFetchUserQueueResponse else {
                            return completionHandler(.success(nil))
                        }

                        do {
                            let userQueue = try self.parseResponseBody(lastCachedResponse, fromCache: true, inboxEnabledHeader: inboxEnabledHeader)
                            let processedQueue = self.processAnonymousMessages(userQueue)

                            completionHandler(.success(processedQueue))
                        } catch {
                            completionHandler(.failure(error))
                        }
                    default:
                        do {
                            let userQueue = try self.parseResponseBody(data, fromCache: false, inboxEnabledHeader: inboxEnabledHeader)

                            // Clear cache only on successful 200 response after successful parsing
                            if response.statusCode == 200 {
                                self.inboxMessageCache.clearAll()
                            }

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

    private func parseResponseBody(_ responseBody: Data, fromCache: Bool, inboxEnabledHeader: Bool?) throws -> [InAppMessageResponse] {
        guard let responseObject = try JSONSerialization.jsonObject(
            with: responseBody,
            options: .allowFragments
        ) as? [String: Any] else {
            logger.logWithModuleTag("Failed to parse queue response, not a JSON object", level: .error)
            return []
        }

        let queueResponse = QueueMessagesResponse(dictionary: responseObject)
        let inboxMessages = queueResponse.inboxMessages
        let inAppMessages = queueResponse.inAppMessages
        logger.logWithModuleTag("Found \(inAppMessages.count) in-app messages, \(inboxMessages.count) inbox messages", level: .debug)

        // For cached responses (304), apply locally cached opened status to preserve user's changes.
        // For fresh responses (200), use server's data as source of truth.
        let inboxMessagesMapped: [InboxMessage]
        if fromCache {
            // 304: Apply cached opened status if available
            inboxMessagesMapped = inboxMessages.map { item -> InboxMessage in
                let message = InboxMessageFactory.fromResponse(item)
                if let cachedOpened = inboxMessageCache.getOpenedStatus(queueId: message.queueId) {
                    return message.copy(opened: cachedOpened)
                }
                return message
            }
        } else {
            // Fresh response: Use server data
            inboxMessagesMapped = inboxMessages.map { InboxMessageFactory.fromResponse($0) }
        }
        // Dispatch inbox messages to update state. Capture the returned task so the pipeline can
        // await the store update before reading `state.inboxMessages`.
        let processTask = inAppMessageManager.dispatch(action: .processInboxMessages(messages: inboxMessagesMapped))

        // Run the visual-inbox data pipeline off the main thread, in ONE ordered task so the steps
        // can't race: (0) wait for the messages-store update to be applied, (1) persist the
        // enablement flag, (2) trigger the templates/branding load when enabled. Messages are read
        // live from the in-app store (updated above via processInboxMessages), so awaiting the
        // dispatch first ensures the pipeline observes the just-applied messages, not stale ones.
        let repository = visualInboxRepository
        Task { [weak self] in
            await processTask.value
            await self?.runInboxPipeline(repository: repository, enabledHeader: inboxEnabledHeader)
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

    /// Reads the `x-cio-inbox-enabled` enablement flag from the queue response headers.
    /// Mirrors `updateSseFlag`. Returns `nil` when the header is absent (cached value left unchanged).
    private func readInboxEnabledHeader(headers: [AnyHashable: Any]) -> Bool? {
        guard let inboxHeaderValue = headers["x-cio-inbox-enabled"] as? String else {
            logger.logWithModuleTag("[CIO-Inbox] x-cio-inbox-enabled header not present in response", level: .debug)
            return nil
        }

        let enabled = inboxHeaderValue.lowercased() == "true"
        logger.logWithModuleTag("[CIO-Inbox] x-cio-inbox-enabled header read: '\(inboxHeaderValue)' -> \(enabled)", level: .info)
        return enabled
    }

    /// Ordered visual-inbox data pipeline run after a poll is parsed.
    ///
    /// Steps run sequentially so they cannot race:
    ///  1. Persist the enablement flag (when the header was present) and detect a `false → true`
    ///     transition for logging.
    ///  2. Always run `enableAndLoad()` so `loadState` is recomputed every poll. `enableAndLoad()`
    ///     self-gates: when the inbox is disabled it sets `loadState = .hidden` and returns without
    ///     fetching; when enabled it performs the initial load (on a transition) or short-circuits on
    ///     a fresh templates/branding cache (later polls), with an in-flight guard preventing
    ///     duplicate concurrent fetches. Calling it unconditionally ensures a workspace that DISABLES
    ///     the inbox flips `loadState` to hidden instead of being left stale at `.visible`. Messages
    ///     are read live from the in-app store at that point, so there is no separate cache here.
    private func runInboxPipeline(
        repository: VisualInboxRepository,
        enabledHeader: Bool?
    ) async {
        // 1) Persist enablement (only when the header was present this poll).
        var previouslyEnabled: Bool?
        if let enabledHeader = enabledHeader {
            previouslyEnabled = await repository.setInboxEnabled(enabledHeader)
            if enabledHeader != previouslyEnabled {
                logger.logWithModuleTag("[CIO-Inbox] enablement transition: \(previouslyEnabled.map(String.init) ?? "unset") -> \(enabledHeader)", level: .info)
            }
        }

        // 2) Always recompute via enableAndLoad(). It self-gates on the disabled case (sets
        //    loadState = .hidden and returns). Only log a fetch when the inbox is actually enabled.
        let enabledNow = await repository.isInboxEnabled
        if enabledNow {
            if previouslyEnabled == false {
                logger.logWithModuleTag("[CIO-Inbox] fetch triggered (enablement false→true transition)", level: .info)
            } else {
                logger.logWithModuleTag("[CIO-Inbox] fetch triggered (enabled poll; fetch-if-missing)", level: .debug)
            }
        }
        await repository.enableAndLoad()
    }
}
