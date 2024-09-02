import CioInternalCommon
import Foundation

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
                return next(.reportError(message: "[InApp] Blocked action: \(action) because userId (\(String(describing: userId))) is invalid"))
            }

            return next(action)
        }
    }
}

func routeMatchingMiddleware(logger: CioInternalCommon.Logger) -> InAppMessageMiddleware {
    middleware { dispatch, getState, next, action in
        let state = getState()
        // Check for page rule match if the action is setting new route and userId is set.
        guard case .setPageRoute = action, let userId = state.userId, !userId.isBlankOrEmpty() else {
            return next(action)
        }

        // Update current route first
        next(action)

        // Check if there is a message currently displayed and if it has a page rule
        let currentRoute = state.currentRoute
        let currentMessage: Message? = state.currentMessageState.activeModalMessage
        let doesCurrentMessageRouteMatch: Bool = currentMessage.flatMap { message in
            message.doesHavePageRule() && (currentRoute.flatMap(message.doesPageRuleMatch) ?? true)
        } ?? true

        // Dismiss the message if updated route does not match message's page rule
        if let message = currentMessage, !doesCurrentMessageRouteMatch {
            logger.debug("[InApp] Dismissing message: \(message.describeForLogs) because route does not match current route: \(String(describing: currentRoute))")
            dispatch(.dismissMessage(message: message, shouldLog: false))
        }

        // Process message queue to check if there is a message that matches the new route
        dispatch(.processMessageQueue(messages: Array(state.messagesInQueue)))
    }
}

func modalMessageDisplayStateMiddleware(logger: CioInternalCommon.Logger, threadUtil: ThreadUtil) -> InAppMessageMiddleware {
    middleware { _, getState, next, action in
        // Continue to next middleware if action is not loadMessage
        guard case .loadMessage(let message, let position) = action else {
            return next(action)
        }

        let state = getState()
        // If there is a message currently displayed, block loading new message
        guard !state.currentMessageState.isDisplayed else {
            let currentMessage = state.currentMessageState.message?.describeForLogs ?? "nil"
            return next(.reportError(message: "[InApp] Blocked loading message: \(message.describeForLogs) because another message is currently displayed or cancelled: \(currentMessage)"))
        }

        logger.debug("[InApp] Showing message: \(message.describeForLogs) with position: \(String(describing: position))")
        // Show message on main thread to avoid unexpected crashes
        threadUtil.runMain {
            let messageManager = MessageManager(siteId: state.siteId, message: message)
            messageManager.showMessage(position: position ?? .center)
        }

        return next(action)
    }
}

private func logMessageView(logger: CioInternalCommon.Logger, state: InAppMessageState, message: Message) {
    LogManager(siteId: state.siteId, dataCenter: state.dataCenter).logView(
        message: message, userToken: state.userId
    ) { response in
        if case .failure(let error) = response {
            logger.error("[InApp] Failed to log message view: \(error) for message: \(message.describeForLogs)")
        }
    }
}

func messageMetricsMiddleware(logger: CioInternalCommon.Logger) -> InAppMessageMiddleware {
    middleware { _, getState, next, action in
        let state = getState()
        switch action {
        case .displayMessage(let message):
            // Log message view only if message is not persistent
            if message.gistProperties.persistent != true {
                logger.debug("[InApp] Message shown, logging view for message: \(message.describeForLogs)")
                logMessageView(logger: logger, state: state, message: message)
            } else {
                logger.debug("[InApp] Persistent message shown, not logging view for message: \(message.describeForLogs)")
            }

        case .dismissMessage(let message, let shouldLog, let viaCloseAction):
            guard shouldLog else { return }

            // Log message close only if message was dismissed via close action
            if viaCloseAction {
                if message.gistProperties.persistent == true {
                    logger.debug("[InApp] Persistent message dismissed, logging view for message: \(message.describeForLogs)")
                } else {
                    logger.debug("[InApp] Dismissed message, logging view for message: \(message.describeForLogs)")
                }
                logMessageView(logger: logger, state: state, message: message)
            } else {
                logger.debug("[InApp] Message dismissed without close action, not logging view for message: \(message.describeForLogs)")
            }

        default:
            break
        }
        return next(action)
    }
}

func messageQueueProcessorMiddleware(logger: CioInternalCommon.Logger) -> InAppMessageMiddleware {
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

                return !state.shownMessageQueueIds.contains(queueId)
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
            logger.debug("[InApp] No message matched the criteria to be shown")
            return
        }

        let elementId = message.gistProperties.elementId
        let nextAction: InAppMessageAction
        if let elementId {
            nextAction = .embedMessage(message: message, elementId: elementId)
        } else {
            nextAction = .loadMessage(message: message)
        }
        // Dispatch action to show the message
        dispatch(nextAction)
    }
}

func messageEventCallbacksMiddleware(delegate: GistDelegate?) -> InAppMessageMiddleware {
    middleware { _, _, next, action in
        // Forward message events to delegate when message is displayed, dismissed or embedded,
        // or when an engine action is received
        switch action {
        case .embedMessage(let message, let elementId):
            delegate?.embedMessage(message: message, elementId: elementId)

        case .displayMessage(let message):
            delegate?.messageShown(message: message)

        case .dismissMessage(let message, _, _):
            delegate?.messageDismissed(message: message)

        case .engineAction(let engineAction):
            switch engineAction {
            case .tap(let message, let route, let name, let action):
                delegate?.action(message: message, currentRoute: route, action: action, name: name)

            case .messageLoadingFailed(let message):
                delegate?.messageError(message: message)

            case .error(let message):
                delegate?.messageError(message: message)
            }

        default:
            break
        }
        next(action)
    }
}

func errorReportingMiddleware(logger: CioInternalCommon.Logger) -> InAppMessageMiddleware {
    middleware { _, _, next, action in
        // Log error messages for reportError actions only
        if case .reportError(let message) = action {
            logger.error("[InApp] Error received: \(message)")
        }

        return next(action)
    }
}
