import CioInternalCommon
import Foundation

/// Represents the state of InAppMessage store.
/// It holds all the information required to manage and identify current state of in-app messaging.
/// It is managed by reducer and should only be updated by dispatching appropriate actions to the store.
struct InAppMessageState: Equatable, CustomStringConvertible {
    let siteId: String
    let dataCenter: String
    let environment: GistEnvironment
    let pollInterval: Double
    let userId: String?
    let currentRoute: String?
    let currentMessageState: ModalMessageState
    let embeddedMessagesState: EmbeddedMessagesState
    let messagesInQueue: Set<Message>
    let shownMessageQueueIds: Set<String>

    init(
        siteId: String = "",
        dataCenter: String = "",
        environment: GistEnvironment = .production,
        pollInterval: Double = 600,
        userId: String? = nil,
        currentRoute: String? = nil,
        currentMessageState: ModalMessageState = .initial,
        embeddedMessagesState: EmbeddedMessagesState = EmbeddedMessagesState(),
        messagesInQueue: Set<Message> = [],
        shownMessageQueueIds: Set<String> = []
    ) {
        self.siteId = siteId
        self.dataCenter = dataCenter
        self.environment = environment
        self.pollInterval = pollInterval
        self.userId = userId
        self.currentRoute = currentRoute
        self.currentMessageState = currentMessageState
        self.embeddedMessagesState = embeddedMessagesState
        self.messagesInQueue = messagesInQueue
        self.shownMessageQueueIds = shownMessageQueueIds
    }

    /// Copies the current state and replaces the given properties with the new values.
    /// It is useful when updating state with only a few properties and keeping the rest as is.
    func copy(
        pollInterval: Double? = nil,
        userId: String? = nil,
        currentRoute: String? = nil,
        currentMessageState: ModalMessageState? = nil,
        embeddedMessagesState: EmbeddedMessagesState? = nil,
        messagesInQueue: Set<Message>? = nil,
        shownMessageQueueIds: Set<String>? = nil
    ) -> InAppMessageState {
        InAppMessageState(
            siteId: siteId,
            dataCenter: dataCenter,
            environment: environment,
            pollInterval: pollInterval ?? self.pollInterval,
            userId: userId ?? self.userId,
            currentRoute: currentRoute ?? self.currentRoute,
            currentMessageState: currentMessageState ?? self.currentMessageState,
            embeddedMessagesState: embeddedMessagesState ?? self.embeddedMessagesState,
            messagesInQueue: messagesInQueue ?? self.messagesInQueue,
            shownMessageQueueIds: shownMessageQueueIds ?? self.shownMessageQueueIds
        )
    }

    static func == (lhs: InAppMessageState, rhs: InAppMessageState) -> Bool {
        lhs.siteId == rhs.siteId &&
            lhs.dataCenter == rhs.dataCenter &&
            lhs.environment == rhs.environment &&
            lhs.pollInterval == rhs.pollInterval &&
            lhs.userId == rhs.userId &&
            lhs.currentRoute == rhs.currentRoute &&
            lhs.currentMessageState == rhs.currentMessageState &&
            lhs.messagesInQueue == rhs.messagesInQueue &&
            lhs.shownMessageQueueIds == rhs.shownMessageQueueIds
    }

    var description: String {
        """
        InAppMessagingState(
            siteId: '\(siteId)',
            dataCenter: '\(dataCenter)',
            environment: \(environment),
            pollInterval: \(pollInterval),
            userId: \(String(describing: userId)),
            currentRoute: \(String(describing: currentRoute)),
            currentMessageState: \(currentMessageState),
            embeddedMessagesState: \(embeddedMessagesState),
            messagesInQueue: \(messagesInQueue.map(\.describeForLogs)),
            shownMessageQueueIds: \(shownMessageQueueIds)
        )
        """
    }
}

extension InAppMessageState {
    /// Returns a dictionary of differences between the previous state and the current state.
    /// It is useful for logging and debugging purposes.
    static func changes(from previousState: InAppMessageState, to currentState: InAppMessageState) -> [String: Any] {
        var diffs: [String: Any] = [:]

        // Helper function to put a key-value pair in diffs if the value is different in current state.
        func putIfDifferent<T: Equatable>(_ keyPath: KeyPath<InAppMessageState, T>, as key: String) {
            if previousState[keyPath: keyPath] != currentState[keyPath: keyPath] {
                diffs[key] = currentState[keyPath: keyPath]
            }
        }

        // Put all the properties from InAppMessageState here to compare them.

        putIfDifferent(\.siteId, as: "siteId")
        putIfDifferent(\.dataCenter, as: "dataCenter")
        putIfDifferent(\.environment, as: "environment")
        putIfDifferent(\.pollInterval, as: "pollInterval")
        putIfDifferent(\.userId, as: "userId")
        putIfDifferent(\.currentRoute, as: "currentRoute")
        putIfDifferent(\.currentMessageState, as: "currentMessageState")
        putIfDifferent(\.embeddedMessagesState, as: "embeddedMessagesState")
        putIfDifferent(\.messagesInQueue, as: "messagesInQueue")
        putIfDifferent(\.shownMessageQueueIds, as: "shownMessageQueueIds")

        return diffs
    }
}

/// Represents various states an in-app message can be in.
/// The states are derived from lifecycle of an in-app message, from loading to displaying to dismissing.
enum ModalMessageState: Equatable, CustomStringConvertible {
    case initial
    case loading(message: Message)
    case displayed(message: Message)
    case dismissed(message: Message)

    static func == (lhs: ModalMessageState, rhs: ModalMessageState) -> Bool {
        switch (lhs, rhs) {
        case (.initial, .initial):
            return true
        case (.loading(let lhsMessage), .loading(let rhsMessage)),
             (.displayed(let lhsMessage), .displayed(let rhsMessage)),
             (.dismissed(let lhsMessage), .dismissed(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }

    var description: String {
        switch self {
        case .initial:
            return "Initial"
        case .loading(let message):
            return "Loading(\(message.describeForLogs))"
        case .displayed(let message):
            return "Displayed(\(message.describeForLogs))"
        case .dismissed(let message):
            return "Dismissed(\(message.describeForLogs))"
        }
    }
}

/// Represents various states an in-app message can be in.
/// The states are derived from lifecycle of an in-app message, from loading to displaying to dismissing.
enum InLineMessageState: Equatable, CustomStringConvertible, Hashable {
    case initial
    case embedded(message: Message, elementId: String)
    case dismissed(message: Message)

    static func == (lhs: InLineMessageState, rhs: InLineMessageState) -> Bool {
        switch (lhs, rhs) {
        case (.initial, .initial):
            return true
        case (.dismissed(let lhsMessage), .dismissed(let rhsMessage)):
            return lhsMessage.queueId == rhsMessage.queueId
        case (.embedded(let lhsMessage, let lhsElementId), .embedded(let rhsMessage, let rhsElementId)):
            return lhsMessage.queueId == rhsMessage.queueId && lhsElementId == rhsElementId
        default:
            return false
        }
    }

    var description: String {
        switch self {
        case .initial:
            return "Initial"
        case .embedded(let message, _):
            return "Embedded(\(message.describeForLogs))"
        case .dismissed(let message):
            return "Dismissed(\(message.describeForLogs))"
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .initial:
            hasher.combine(0)
        case .embedded(let message, _),
             .dismissed(let message):
            hasher.combine(message.queueId)
        }
    }
}

/// In Swift, comparing enum cases with associated values directly can be cumbersome.
/// This extension simplifies access to `Message` associated with each state and
/// provides boolean properties that make it easy to check whether a `MessageState`
/// is currently in a specific state (e.g., loading, displayed, embedded, or dismissed).
extension ModalMessageState {
    var message: Message? {
        switch self {
        case .initial:
            return nil
        case .loading(let message),
             .displayed(let message),
             .dismissed(let message):
            return message
        }
    }

    /// Returns the message associated with the state only if the state is `loading` or `displayed`.
    var activeModalMessage: Message? {
        switch self {
        case .initial,
             .dismissed:
            return nil
        case .loading(let message),
             .displayed(let message):
            return message
        }
    }

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var isDisplayed: Bool {
        if case .displayed = self {
            return true
        }
        return false
    }

    var isDismissed: Bool {
        if case .dismissed = self {
            return true
        }
        return false
    }
}

extension InLineMessageState {
    var message: Message? {
        switch self {
        case .initial:
            return nil
        case .embedded(let message, _):
            return message
        case .dismissed(let message):
            return message
        }
    }

    var elementId: String? {
        switch self {
        case .initial:
            return nil
        case .embedded(_, let elementId):
            return elementId
        case .dismissed(let message):
            return message.elementId
        }
    }

    var isDismissed: Bool {
        if case .dismissed = self {
            return true
        }
        return false
    }

    var isEmbedded: Bool {
        if case .embedded = self {
            return true
        }
        return false
    }
}

struct EmbeddedMessagesState: Equatable {
    private var messagesById: [String: InLineMessageState] = [:] // Keyed by queueId
    private var elementToMessageIds: [String: String] = [:] // Maps elementId -> queueId

    // Add or update a message
    mutating func add(message: Message, elementId: String) {
        guard let messageId = message.queueId else { return }

        let state = InLineMessageState.embedded(message: message, elementId: elementId)
        messagesById[messageId] = state
        elementToMessageIds[elementId] = messageId
    }

    // Remove a message by its messageId
    mutating func remove(messageId: String) {
        guard let state = messagesById[messageId],
              let elementId = state.elementId else { return }

        // Remove from messagesById
        messagesById[messageId] = nil

        // Remove the mapping in elementToMessageIds
        if elementToMessageIds[elementId] == messageId {
            elementToMessageIds[elementId] = nil
        }
    }

    // Fetch the message currently associated with an elementId
    func getMessage(forElementId elementId: String) -> InLineMessageState? {
        guard let messageId = elementToMessageIds[elementId] else { return nil }
        return messagesById[messageId]
    }

    // Fetch all messages for debugging or iteration
    func allMessages() -> [InLineMessageState] {
        Array(messagesById.values)
    }

    // Conformance to Equatable
    static func == (lhs: EmbeddedMessagesState, rhs: EmbeddedMessagesState) -> Bool {
        lhs.messagesById == rhs.messagesById &&
            lhs.elementToMessageIds == rhs.elementToMessageIds
    }
}

extension EmbeddedMessagesState {
    // Dismiss the message for a given elementId
    mutating func dismissMessage(forElementId elementId: String) {
        guard let messageId = elementToMessageIds[elementId],
              let existingState = messagesById[messageId] else { return }

        // Update the state of the message to dismissed
        let dismissedState = InLineMessageState.dismissed(message: existingState.message!)
        messagesById[messageId] = dismissedState

        // Remove the mapping from elementToMessageIds
        elementToMessageIds[elementId] = nil
    }

    // Dismiss a specific message by messageId
    mutating func dismissMessage(withMessageId messageId: String) {
        guard let existingState = messagesById[messageId] else { return }

        // Update the state of the message to dismissed
        let dismissedState = InLineMessageState.dismissed(message: existingState.message!)
        messagesById[messageId] = dismissedState
    }
}
