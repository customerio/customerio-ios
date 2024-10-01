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

        // Block actions that require valid userId unless userId is set.
        switch action {
        case .initialize,
             .setUserIdentifier,
             .setPageRoute,
             .resetState:
            return next(action)

        default:
            let userId = state.userId
            guard let userId = userId, !userId.isBlankOrEmpty() else {
                return next(.reportError(message: "Blocked action: \(action) because userId (\(String(describing: userId))) is invalid"))
            }

            return next(action)
        }
    }
}

func routeMatchingMiddleware(logger: Logger) -> InAppMessageMiddleware {
    middleware { dispatch, getState, next, action in
        let state = getState()
        // Check for page rule match if the action is setting new route and userId is set.
        guard case .setPageRoute(let currentRoute) = action, let userId = state.userId, !userId.isBlankOrEmpty() else {
            return next(action)
        }

        // Update current route first
        next(action)

        // Check if there is a message displayed and if it has a page rule
        // If the message does not have a page rule, it will continue to be displayed
        // If the message has a page rule, it will be dismissed only if updated route does not match message's page rule
        if let message = state.currentMessageState.activeModalMessage,
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
        guard !state.currentMessageState.isDisplayed else {
            let currentMessage = state.currentMessageState.message?.describeForLogs ?? "nil"
            return next(.reportError(message: "Blocked loading message: \(message.describeForLogs) because another message is currently displayed or cancelled: \(currentMessage)"))
        }

        logger.logWithModuleTag("Showing message: \(message)", level: .debug)
        // Show message on main thread to avoid unexpected crashes
        threadUtil.runMain {
            let messageManager = MessageManager(state: state, message: message)
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

func messageMetricsMiddleware(logger: Logger, logManager: LogManager) -> InAppMessageMiddleware {
    middleware { _, getState, next, action in
        let state = getState()
        switch action {
        case .displayMessage(let message):
            // Log message view only if message should be tracked as shown on display action
            if action.shouldMarkMessageAsShown {
                logger.logWithModuleTag("Message shown, logging view for message: \(message.describeForLogs)", level: .debug)
                logMessageView(logger: logger, logManager: logManager, state: state, message: message)
            } else {
                logger.logWithModuleTag("Persistent message shown, not logging view for message: \(message.describeForLogs)", level: .debug)
            }

        case .dismissMessage(let message, let shouldLog, let viaCloseAction):
            // Log message close only if message should be tracked as shown on dismiss action
            if action.shouldMarkMessageAsShown {
                logger.logWithModuleTag("Persistent message dismissed, logging view for message: \(message.describeForLogs), shouldLog: \(shouldLog), viaCloseAction: \(viaCloseAction)", level: .debug)
                logMessageView(logger: logger, logManager: logManager, state: state, message: message)
            } else {
                logger.logWithModuleTag("Message dismissed, not logging view for message: \(message.describeForLogs), shouldLog: \(shouldLog), viaCloseAction: \(viaCloseAction)", level: .debug)
            }

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

                // Filter out messages that have been shown already, or if the message is embedded
                return !state.shownMessageQueueIds.contains(queueId) && message.gistProperties.elementId == nil
            }
            .reduce(into: [Message]()) { result, message in
                if !result.contains(where: { $0.queueId == message.queueId }) {
                    result.append(message)
                }
            }
            .sorted { ($0.priority ?? Int.max) < ($1.priority ?? Int.max) }

        // Find the first message that matches the current route or has no page rule
        // Since messages are sorted by priority, the first message will be the one with the highest priority
        let messageToBeShown = notShownMessages.first { message in
            let currentRoute = state.currentRoute

            if message.doesHavePageRule() {
                guard let currentRoute else { return false }

                return message.doesPageRuleMatch(route: currentRoute)
            }
            return true
        }

        let isCurrentMessageLoading = state.currentMessageState.isLoading
        let isCurrentMessageDisplaying = state.currentMessageState.isDisplayed
        // Dispatch next action to process remaining messages
        next(.processMessageQueue(messages: notShownMessages))

        // If there is a message currently displayed or loading, do not show another message
        guard let message = messageToBeShown,
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

func messageEventCallbacksMiddleware(delegate: GistDelegate) -> InAppMessageMiddleware {
    middleware { _, _, next, action in
        // Forward message events to delegate when message is displayed, dismissed or embedded,
        // or when an engine action is received
        switch action {
        case .embedMessage(let message, let elementId):
            delegate.embedMessage(message: message, elementId: elementId)

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
