import CioInternalCommon
import Foundation

/// Returns a reducer function after wrapping it in a logging function.
/// The wrapper function logs the action and state before and after the reducer is called.
/// Also, it ensures that the action is of type InAppMessageAction and utilizes custom defined types instead
/// of referring to ReSwift's Action type directly.
func inAppMessageReducer(logger: Logger) -> InAppMessageReducer {
    { action, state in
        let currentState = state ?? InAppMessageState()
        logger.logWithModuleTag("Action received: \(action) with current state: \(currentState)", level: .debug)
        let result = reducer(action: action, state: currentState)

        let changes = InAppMessageState.changes(from: currentState, to: result)
        if !changes.isEmpty {
            logger.logWithModuleTag("State changes after action '\(action)': \(changes)", level: .debug)
        } else {
            logger.logWithModuleTag("No state changes after action '\(action)'", level: .debug)
        }

        return result
    }
}

// swiftlint:disable cyclomatic_complexity function_body_length
/// Reducer function implementation for managing InAppMessageState based on the action received.
private func reducer(action: InAppMessageAction, state: InAppMessageState) -> InAppMessageState {
    switch action {
    case .initialize(let siteId, let dataCenter, let environment):
        return InAppMessageState(siteId: siteId, dataCenter: dataCenter, environment: environment)

    case .setPollingInterval(let interval):
        return state.copy(pollInterval: interval)

    case .setUserIdentifier(let user):
        return state.copy(userId: user)

    case .setPageRoute(let route):
        return state.copy(currentRoute: route)

    case .processMessageQueue(let messages):
        return state.copy(messagesInQueue: Set(messages))

    case .embedMessages(let messages):
        var newEmbeddedMessages = state.embeddedMessagesState
        for message in messages {
            if let elementId = message.elementId {
                newEmbeddedMessages.add(message: message, elementId: elementId)
            }
        }
        return state.copy(embeddedMessagesState: newEmbeddedMessages)

    case .clearMessageQueue:
        return state.copy(messagesInQueue: [])

    case .loadMessage(let message):
        return state.copy(modalMessageState: .loading(message: message))

    case .displayMessage(let message):
        guard let queueId = message.queueId else { return state }

        // Update shownMessageQueueIds if the message should be tracked
        let shownMessageQueueIds = action.shouldMarkMessageAsShown
            ? state.shownMessageQueueIds.union([queueId])
            : state.shownMessageQueueIds

        // Remove the message from the queue
        let messagesInQueue = state.messagesInQueue.filter { $0.queueId != queueId }

        if message.isEmbedded {
            // Update embedded message state
            return state.updateEmbeddedMessage(
                queueId: queueId,
                newState: .embedded(message: message, elementId: message.elementId ?? ""),
                shownMessageQueueIds: shownMessageQueueIds,
                messagesInQueue: messagesInQueue
            )
        }

        // Update modal message state
        return state.copy(
            modalMessageState: .displayed(message: message),
            messagesInQueue: messagesInQueue,
            shownMessageQueueIds: shownMessageQueueIds
        )

    case .dismissMessage(let message, _, _):
        let shownMessageQueueIds = action.shouldMarkMessageAsShown && message.queueId != nil
            ? state.shownMessageQueueIds.union([message.queueId!])
            : state.shownMessageQueueIds

        if message.isEmbedded, let queueId = message.queueId {
            // Update embedded message state
            return state.updateEmbeddedMessage(
                queueId: queueId,
                newState: InlineMessageState.dismissed(message: message),
                shownMessageQueueIds: shownMessageQueueIds
            )
        }

        // Update modal message state
        return state.copy(
            modalMessageState: .dismissed(message: message),
            shownMessageQueueIds: shownMessageQueueIds
        )

    case .engineAction(let engineAction):
        switch engineAction {
        case .tap:
            return state
        case .messageLoadingFailed(let message):
            return state.copy(modalMessageState: .dismissed(message: message))
        }

    case .reportError:
        return state

    case .resetState:
        return InAppMessageState(
            siteId: state.siteId,
            dataCenter: state.dataCenter,
            environment: state.environment
        )
    }
}

// swiftlint:enable cyclomatic_complexity function_body_length
