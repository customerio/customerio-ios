import CioInternalCommon
import Foundation

/// Helper function to create middleware for InAppMessage module
/// - Parameter completion: A closure that takes in the necessary parameters to perform the middleware logic
/// - Returns: Middleware function with given completion closure
private func middleware(
    completion: @escaping MiddlewareCompletion
) -> InAppMessageMiddleware {
    { dispatch,
        // swiftlint:disable:next closure_parameter_position
        getState in {
            // swiftlint:disable:next closure_parameter_position
            next in {
                // swiftlint:disable:next closure_parameter_position
                action in
                let getStateOrDefault = { getState() ?? InAppMessageState() }
                completion(dispatch, getStateOrDefault, next, action)
            }
        }
    }
}

func userAuthenticationMiddleware() -> InAppMessageMiddleware {
    middleware { _, getState, next, action in
        let state = getState()

        // Block actions that require valid userId or anonymousId unless at least one is set.
        switch action {
        case .initialize,
             .setUserIdentifier,
             .setAnonymousIdentifier,
             .setPageRoute,
             .resetState:
            return next(action)

        default:
            let userId = state.userId
            let anonymousId = state.anonymousId

            // Allow action if either userId or anonymousId is valid
            if let userId = userId, !userId.isBlankOrEmpty() {
                return next(action)
            } else if let anonymousId = anonymousId, !anonymousId.isBlankOrEmpty() {
                return next(action)
            } else {
                return next(.reportError(message: "Blocked action: \(action) because neither userId (\(String(describing: userId))) nor anonymousId (\(String(describing: anonymousId))) is valid"))
            }
        }
    }
}

func routeMatchingMiddleware(logger: Logger) -> InAppMessageMiddleware {
    middleware { dispatch, getState, next, action in
        let state = getState()
        // Check for page rule match if the action is setting new route and either userId or anonymousId is set.
        guard case .setPageRoute(let currentRoute) = action else {
            return next(action)
        }

        // Require either userId or anonymousId to be present
        let hasUserId = state.userId.map { !$0.isBlankOrEmpty() } ?? false
        let hasAnonymousId = state.anonymousId.map { !$0.isBlankOrEmpty() } ?? false
        guard hasUserId || hasAnonymousId else {
            return next(action)
        }

        // Update current route first
        next(action)

        // Check if there is a message displayed and if it has a page rule
        // If the message does not have a page rule, it will continue to be displayed
        // If the message has a page rule, it will be dismissed only if updated route does not match message's page rule
        if let message = state.modalMessageState.activeModalMessage,
           message.doesHavePageRule(),
           !message.doesPageRuleMatch(route: currentRoute) {
            // Dismiss message if the route does not match new route
            logger.logWithModuleTag("Dismissing message: \(message.describeForLogs) because route does not match current route: \(currentRoute)", level: .debug)
            dispatch(.dismissMessage(message: message, shouldLog: false))
        }

        // Process message queue to check if there is a message that matches the new route
        dispatch(.processMessageQueue(messages: Array(state.messagesInQueue)))
    }
}

func modalMessageDisplayStateMiddleware(logger: Logger, threadUtil: ThreadUtil) -> InAppMessageMiddleware {
    middleware { _, getState, next, action in
        // Continue to next middleware if action is not loadMessage
        guard case .loadMessage(let message) = action else {
            return next(action)
        }

        let state = getState()
        // If there is a message currently displayed, block loading new message
        guard !state.modalMessageState.isDisplayed else {
            let currentMessage = state.modalMessageState.message?.describeForLogs ?? "nil"
            return next(.reportError(message: "Blocked loading message: \(message.describeForLogs) because another message is currently displayed or cancelled: \(currentMessage)"))
        }

        logger.logWithModuleTag("Showing message: \(message)", level: .debug)
        // Show message on main thread to avoid unexpected crashes
        threadUtil.runMain {
            let messageManager = ModalMessageManager(state: state, message: message)
            messageManager.showMessage()
        }

        return next(action)
    }
}

private func logMessageView(logger: Logger, logManager: LogManager, state: InAppMessageState, message: Message) {
    logManager.logView(state: state, message: message) { response in
        if case .failure(let error) = response {
            logger.logWithModuleTag("Failed to log message view: \(error) for message: \(message.describeForLogs)", level: .error)
        }
    }
}

func messageMetricsMiddleware(logger: Logger, logManager: LogManager, anonymousMessageManager: AnonymousMessageManager) -> InAppMessageMiddleware {
    middleware { dispatch, getState, next, action in
        let state = getState()
        switch action {
        case .displayMessage(let message):
            // Handle anonymous message tracking
            if message.isAnonymousMessage {
                logger.logWithModuleTag("Anonymous message shown, tracking locally: \(message.describeForLogs)", level: .debug)
                anonymousMessageManager.markMessageAsSeen(messageId: message.messageId)
            }

            // Log message view only if message should be tracked as shown on display action
            if action.shouldMarkMessageAsShown {
                logger.logWithModuleTag("Message shown, logging view for message: \(message.describeForLogs)", level: .debug)
                logMessageView(logger: logger, logManager: logManager, state: state, message: message)
            } else {
                logger.logWithModuleTag("Persistent message shown, not logging view for message: \(message.describeForLogs)", level: .debug)
            }

        case .dismissMessage(let message, let shouldLog, let viaCloseAction):
            // Handle anonymous message dismissal tracking
            if message.isAnonymousMessage, shouldLog {
                logger.logWithModuleTag("Anonymous message dismissed, tracking locally: \(message.describeForLogs)", level: .debug)
                anonymousMessageManager.markMessageAsDismissed(messageId: message.messageId)
            }

            // Log message close only if message should be tracked as shown on dismiss action
            if action.shouldMarkMessageAsShown {
                logger.logWithModuleTag("Persistent message dismissed, logging view for message: \(message.describeForLogs), shouldLog: \(shouldLog), viaCloseAction: \(viaCloseAction)", level: .debug)
                logMessageView(logger: logger, logManager: logManager, state: state, message: message)
            } else {
                logger.logWithModuleTag("Message dismissed, not logging view for message: \(message.describeForLogs), shouldLog: \(shouldLog), viaCloseAction: \(viaCloseAction)", level: .debug)
            }

            // Process the DismissMessage action first so the reducer can update shownMessageQueueIds
            // This ensures the dismissed message is properly marked as shown before processing the queue
            next(action)

            // After the dismissal is processed, dispatch ProcessMessageQueue to show the next message
            // This matches Android's behavior in gistLoggingMessageMiddleware where it dispatches
            // ProcessMessageQueue(store.state.messagesInQueue) after DismissMessage when SSE is enabled.
            // The dismissed message will be filtered out by messageQueueProcessorMiddleware
            // since its queueId is now in shownMessageQueueIds
            if state.shouldUseSse {
                logger.logWithModuleTag("SSE enabled - Processing message queue after dismissal to show next message", level: .debug)
                dispatch(.processMessageQueue(messages: Array(state.messagesInQueue)))
            }
            return

        default:
            break
        }

        return next(action)
    }
}

func messageQueueProcessorMiddleware(logger: Logger) -> InAppMessageMiddleware {
    middleware { dispatch, getState, next, action in
        // Continue to next middleware if action is not processMessageQueue or if messages are empty
        guard case .processMessageQueue(let messages) = action, !messages.isEmpty else {
            return next(action)
        }

        let state = getState()
        // Filter out messages with valid queueId that have not been shown yet and sort by priority
        let notShownMessages = messages
            .filter { message in
                guard let queueId = message.queueId else { return false }

                // Filter out messages that have been shown already
                return !state.shownMessageQueueIds.contains(queueId)
            }
            .reduce(into: [Message]()) { result, message in
                if !result.contains(where: { $0.queueId == message.queueId }) {
                    result.append(message)
                }
            }
            .sorted { ($0.priority ?? Int.max) < ($1.priority ?? Int.max) }

        // Split into modal and embedded messages
        let modalMessages = notShownMessages.filter { !$0.isEmbedded }
        let embeddedMessages = notShownMessages.filter(\.isEmbedded)

        let isCurrentMessageLoading = state.modalMessageState.isLoading
        let isCurrentMessageDisplaying = state.modalMessageState.isDisplayed
        // Dispatch next action to process remaining messages
        next(.processMessageQueue(messages: notShownMessages))

        // Handle embedded messages
        let embedMessagesToBeShown = embeddedMessages
            .filter { $0.messageMatchesRoute(state.currentRoute) }
            .filter { message in
                // Ensure no duplicate embedded messages for the same elementId in the `.embedded` state
                guard let elementId = message.elementId else { return true }
                if let existingState = state.embeddedMessagesState.getMessage(forElementId: elementId),
                   case .embedded = existingState {
                    return false // Exclude if the existing state is `.embedded`
                }
                return true // Include if no `.embedded` message exists for this elementId
            }

        if !embedMessagesToBeShown.isEmpty {
            dispatch(.embedMessages(messages: embedMessagesToBeShown))
        }

        // Find the first message that matches the current route or has no page rule
        // Since messages are sorted by priority, the first message will be the one with the highest priority
        let modelMessageToBeShown = modalMessages.first { message in
            message.messageMatchesRoute(state.currentRoute)
        }

        // If there is a message currently displayed or loading, do not show another message
        guard let message = modelMessageToBeShown,
              !isCurrentMessageLoading,
              !isCurrentMessageDisplaying
        else {
            // Log if no message matched the criteria to be shown
            // This can happen if there is a message currently displayed or loading
            // or if there are no messages in the queue that match the current route
            logger.logWithModuleTag("No message matched the criteria to be shown", level: .debug)
            // We don't need to dispatch next action to process remaining messages since processMessageQueue was already dispatched above
            return
        }

        // Dispatch action to show the message
        dispatch(.loadMessage(message: message))
    }
}

func inboxMessageMiddleware(logger: Logger) -> InAppMessageMiddleware {
    middleware { _, _, next, action in
        // For now, just pass through the action
        // Future PRs will add implement API calls and change listeners
        if case .processInboxMessages(let messages) = action {
            logger.logWithModuleTag("Processing \(messages.count) inbox messages", level: .debug)
        }

        return next(action)
    }
}

func messageEventCallbacksMiddleware(delegate: GistDelegate) -> InAppMessageMiddleware {
    middleware { _, _, next, action in
        // Forward message events to delegate when message is displayed, dismissed or embedded,
        // or when an engine action is received
        switch action {
        case .displayMessage(let message):
            delegate.messageShown(message: message)

        case .dismissMessage(let message, _, _):
            delegate.messageDismissed(message: message)

        case .engineAction(let engineAction):
            switch engineAction {
            case .tap(let message, let route, let name, let action):
                delegate.action(message: message, currentRoute: route, action: action, name: name)

            case .messageLoadingFailed(let message):
                delegate.messageError(message: message)
            }

        default:
            break
        }
        next(action)
    }
}

func errorReportingMiddleware(logger: Logger) -> InAppMessageMiddleware {
    middleware { _, _, next, action in
        // Log error messages for reportError actions only
        if case .reportError(let message) = action {
            logger.logWithModuleTag("Error received: \(message)", level: .error)
        }

        return next(action)
    }
}
