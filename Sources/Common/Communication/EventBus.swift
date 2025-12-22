import Foundation

/// A tokent that maintains a registration by its retention. When this token is deallocated,
/// the registration that generated it will be removed.
public protocol RegistrationToken: AnyObject, Sendable { }


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

    private let _observers: Synchronized<[String: [NSObjectProtocol]]> = .init(initial: [:])
    
    func storeObserver(_ observer: NSObjectProtocol, for eventKey: String) {
        let eventKey = String(describing: eventKey)
        _observers.mutating { value in
            if value[eventKey] == nil {
                value[eventKey] = []
            }
            value[eventKey]!.append(observer)
        }
    }
    
    func hasObservers(for eventKey: String) -> Bool {
        return _observers.wrappedValue[eventKey, default: []].isEmpty == false
    }

    func removeReservers(for eventKey: String) {
        _observers.mutating { value in
            value[eventKey]?.forEach(notificationCenter.removeObserver)
            value[eventKey] = nil
        }
    }
    
    /// Removes all observers from the EventBus.
    ///
    /// This function is used for cleanup or resetting the event handling system.
    func removeAllObservers() {
        _observers.mutating { value in
            value.forEach { _, list in
                list.forEach(notificationCenter.removeObserver)
            }
            value.removeAll()
        }
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
        if holder.hasObservers(for: key) {
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
    func addObserver(_ eventKey: String, action: @escaping (AnyEventRepresentable) -> Void) async {
        let observer = holder.notificationCenter.addObserver(forName: NSNotification.Name(eventKey), object: nil, queue: nil) { notification in
            if let event = notification.object as? AnyEventRepresentable {
                action(event)
            }
        }
        holder.storeObserver(observer, for: eventKey)
    }

    /// Removes all observers for a specific event type.
    ///
    /// - Parameter eventKey: The event type for which to remove all observers.
    func removeObserver(for eventKey: String) {
        holder.removeReservers(for: eventKey)
    }
}
