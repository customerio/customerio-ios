import Foundation
import ReSwift

/// Represents an action that can be dispatched to InAppMessage store.
/// It acts like a sealed class, so that only the cases defined here can be used with InAppMessage store.
enum InAppMessageAction: Equatable, Action {
    case initialize(siteId: String, dataCenter: String, environment: GistEnvironment)
    case setPollingInterval(interval: Double)
    case setUserIdentifier(user: String)
    case setPageRoute(route: String)
    case processMessageQueue(messages: [Message])
    case clearMessageQueue
    case loadMessage(message: Message, position: MessagePosition? = nil)
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
        case error(message: Message)
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

        case (.loadMessage(let lhsMessage, let lhsPosition), .loadMessage(let rhsMessage, let rhsPosition)):
            return lhsMessage == rhsMessage && lhsPosition == rhsPosition

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