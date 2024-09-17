import Foundation

/// Represents an action that can be dispatched to InAppMessage store.
/// It acts like a sealed class, so that only the cases defined here can be used with InAppMessage store.
enum InAppMessageAction: Equatable {
    case initialize(siteId: String, dataCenter: String, environment: GistEnvironment)
    case setPollingInterval(interval: Double)
    case setUserIdentifier(user: String)
    case setPageRoute(route: String)
    case processMessageQueue(messages: [Message])
    case clearMessageQueue
    case loadMessage(message: Message)
    case embedMessage(message: Message, elementId: String)
    case displayMessage(message: Message)
    case dismissMessage(message: Message, shouldLog: Bool = true, viaCloseAction: Bool = true)
    case reportError(message: String)
    case engineAction(action: EngineAction)
    case resetState

    /// Represents an action that can be dispatched to InAppMessage store.
    /// It only contains actions that are related to Gist engine view.
    enum EngineAction: Equatable {
        case tap(message: Message, route: String, name: String, action: String)
        case messageLoadingFailed(message: Message)
    }

    // swiftlint:disable cyclomatic_complexity
    static func == (lhs: InAppMessageAction, rhs: InAppMessageAction) -> Bool {
        switch (lhs, rhs) {
        case (.initialize(let lhsSiteId, let lhsDataCenter, let lhsEnvironment), .initialize(let rhsSiteId, let rhsDataCenter, let rhsEnvironment)):
            return lhsSiteId == rhsSiteId && lhsDataCenter == rhsDataCenter && lhsEnvironment == rhsEnvironment

        case (.setPollingInterval(let lhsInterval), .setPollingInterval(let rhsInterval)):
            return lhsInterval == rhsInterval

        case (.setUserIdentifier(let lhsUser), .setUserIdentifier(let rhsUser)):
            return lhsUser == rhsUser

        case (.setPageRoute(let lhsRoute), .setPageRoute(let rhsRoute)):
            return lhsRoute == rhsRoute

        case (.processMessageQueue(let lhsMessages), .processMessageQueue(let rhsMessages)):
            return lhsMessages == rhsMessages

        case (.clearMessageQueue, .clearMessageQueue):
            return true

        case (.loadMessage(let lhsMessage), .loadMessage(let rhsMessage)):
            return lhsMessage == rhsMessage

        case (.embedMessage(let lhsMessage, let lhsElementId), .embedMessage(let rhsMessage, let rhsElementId)):
            return lhsMessage == rhsMessage && lhsElementId == rhsElementId

        case (.displayMessage(let lhsMessage), .displayMessage(let rhsMessage)):
            return lhsMessage == rhsMessage

        case (.dismissMessage(let lhsMessage, let lhsShouldLog, let lhsViaCloseAction), .dismissMessage(let rhsMessage, let rhsShouldLog, let rhsViaCloseAction)):
            return lhsMessage == rhsMessage && lhsShouldLog == rhsShouldLog && lhsViaCloseAction == rhsViaCloseAction

        case (.reportError(let lhsMessage), .reportError(let rhsMessage)):
            return lhsMessage == rhsMessage

        case (.engineAction(let lhsAction), .engineAction(let rhsAction)):
            return lhsAction == rhsAction

        case (.resetState, .resetState):
            return true

        default:
            return false
        }
    }
    // swiftlint:enable cyclomatic_complexity
}

extension InAppMessageAction {
    /// Determines whether the message should be tracked viewed and added to `shownMessageQueueIds` or not.
    ///
    /// - Returns: `true` if the message is non-persistent in `displayMessage` case or if it's persistent and
    ///   meets the conditions in `dismissMessage` case, otherwise `false`.
    var shouldMarkMessageAsShown: Bool {
        switch self {
        case .displayMessage(let message):
            // Mark the message as shown if it's not persistent
            return message.gistProperties.persistent != true

        case .dismissMessage(let message, let shouldLog, let viaCloseAction):
            // Mark the message as shown if it's persistent and should be logged and dismissed via close action only
            return message.gistProperties.persistent == true && shouldLog && viaCloseAction

        default:
            return false
        }
    }
}
