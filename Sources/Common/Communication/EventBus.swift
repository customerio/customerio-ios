import Foundation

/// Defines the contract for an event bus system.
///
/// This protocol outlines the core functionalities of an event bus, including posting events,
/// adding observers, and managing observers. It is designed to support type-safe event handling
/// and asynchronous execution
public protocol EventBus: AutoMockable {
    /// Posts an event to all registered observers.
    ///
    /// - Parameters:
    ///   - event: The event to be posted.
    /// - Returns: A Boolean indicating if the event was posted to any observers.
    @discardableResult
    func post(_ event: AnyEventRepresentable) async -> Bool
    /// Adds an observer for a specific event type.
    ///
    /// - Parameters:
    ///   - eventType: The event type to observe.
    ///   - action: The action to execute when the event is observed.
    func addObserver(_ eventType: String, action: @escaping (AnyEventRepresentable) -> Void) async
    /// Removes all observers for a specific event type.
    ///
    /// - Parameter eventType: The event type for which to remove observers.
    func removeObserver(for eventType: String) async
}

// swiftlint:disable orphaned_doc_comment
/// EventBusObserversHolder is a private helper class used within SharedEventBus.
/// It manages observers for different event types and interacts with NotificationCenter.
/// This class is intended to be used exclusively by SharedEventBus to encapsulate
/// the details of observer management and ensure thread-safe operations.
///
/// - Note: This class should remain private to SharedEventBus and not be exposed
///         or used externally to maintain encapsulation and thread safety.
// sourcery: InjectRegisterShared = "EventBusObserversHolder"
// sourcery: InjectSingleton
// swiftlint:enable orphaned_doc_comment
class EventBusObserversHolder {
    /// NotificationCenter instance used for observer management.
    let notificationCenter: NotificationCenter = .default

    /// Dictionary holding arrays of observer tokens for each event type.
    /// The keys are event types (as String), and the values are arrays of NotificationCenter tokens.
    var observers: [String: [NSObjectProtocol]] = [:]

    /// Removes all observers from the EventBus.
    ///
    /// This function is used for cleanup or resetting the event handling system.
    func removeAllObservers() {
        observers.forEach { _, observerList in
            observerList.forEach(notificationCenter.removeObserver)
        }
        observers.removeAll()
    }

    /// Deinitializer for EventBusObserversHolder.
    /// Ensures that all observers are removed from NotificationCenter upon deinitialization.
    deinit {
        self.removeAllObservers()
    }
}

// swiftlint:disable orphaned_doc_comment
/// A shared implementation of `EventBus` using an actor model for thread-safe operations.
/// This actor manages the distribution of events to registered observers and uses
/// `NotificationCenter` for event delivery. It ensures that event handling is thread-safe
/// and observers are managed efficiently.
// sourcery: InjectRegisterShared = "EventBus"
// sourcery: InjectSingleton
// swiftlint:enable orphaned_doc_comment
actor SharedEventBus: EventBus {
    private let holder: EventBusObserversHolder

    init(holder: EventBusObserversHolder) {
        self.holder = holder

        DIGraphShared.shared.logger.debug("SharedEventBus initialized")
    }

    /// Posts an event to all registered observers of its type.
    ///
    /// - Parameter event: The event to be posted.
    /// - Returns: True if the event has been posted to any observers, false otherwise.
    @discardableResult
    func post(_ event: AnyEventRepresentable) -> Bool {
        let key = event.key
        if let observerList = holder.observers[key], !observerList.isEmpty {
            holder.notificationCenter.post(name: NSNotification.Name(key), object: event)
            return true
        }
        return false
    }

    /// Registers an observer for a specific event type.
    ///
    /// - Parameters:
    ///   - eventType: The type of the event to observe.
    ///   - action: The action to be executed when the event is received.
    func addObserver(_ eventType: String, action: @escaping (AnyEventRepresentable) -> Void) async {
        let observer = holder.notificationCenter.addObserver(forName: NSNotification.Name(eventType), object: nil, queue: nil) { notification in
            if let event = notification.object as? AnyEventRepresentable {
                action(event)
            }
        }
        // Store the observer reference for later management.
        if holder.observers[eventType] != nil {
            holder.observers[eventType]?.append(observer)
        } else {
            holder.observers[eventType] = [observer]
        }
    }

    /// Removes all observers for a specific event type.
    ///
    /// - Parameter eventType: The event type for which to remove all observers.
    func removeObserver(for eventType: String) {
        if let observerList = holder.observers[eventType] {
            for observer in observerList {
                holder.notificationCenter.removeObserver(observer)
            }
            holder.observers[eventType] = nil
        }
    }
}
