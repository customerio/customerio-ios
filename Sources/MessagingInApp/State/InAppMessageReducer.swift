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

    case .clearMessageQueue:
        return state.copy(messagesInQueue: [])

    case .loadMessage(let message):
        return state.copy(currentMessageState: .loading(message: message))

    case .displayMessage(let message):
        if let queueId = message.queueId {
            // If the message should be tracked shown when it is displayed, add the queueId to shownMessageQueueIds.
            let shownMessageQueueIds = action.shouldMarkMessageAsShown
                ? state.shownMessageQueueIds.union([queueId])
                : state.shownMessageQueueIds

            return state.copy(
                currentMessageState: .displayed(message: message),
                messagesInQueue: state.messagesInQueue.filter { $0.queueId != queueId },
                shownMessageQueueIds: shownMessageQueueIds
            )
        }
        return state

    case .dismissMessage(let message, _, _):
        var shownMessageQueueIds = state.shownMessageQueueIds
        // If the message should be tracked shown when it is dismissed, add the queueId to shownMessageQueueIds.
        if action.shouldMarkMessageAsShown, let queueId = message.queueId {
            shownMessageQueueIds = shownMessageQueueIds.union([queueId])
        }

        return state.copy(
            currentMessageState: .dismissed(message: message),
            shownMessageQueueIds: shownMessageQueueIds
        )

    case .engineAction(let engineAction):
        switch engineAction {
        case .tap:
            return state
        case .messageLoadingFailed(let message):
            return state.copy(currentMessageState: .dismissed(message: message))
        }

    case .embedMessage,
         .reportError:
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
