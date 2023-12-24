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
    /// Removes all registered observers from the EventBus.
    func removeAllObservers() async
    /// Removes all observers for a specific event type.
    ///
    /// - Parameter eventType: The event type for which to remove observers.
    func removeObserver(for eventType: String) async
}

/// A shared implementation of `EventBus` using an actor model for thread-safe operations.
/// This actor manages the distribution of events to registered observers and uses
/// `NotificationCenter` for event delivery. It ensures that event handling is thread-safe
/// and observers are managed efficiently.
// sourcery: InjectRegisterShared = "EventBus"
// sourcery: InjectSingleton
actor SharedEventBus: EventBus {
    private var notificationCenter: NotificationCenter = .default
    private var observers: [String: [NSObjectProtocol]] = [:]

    deinit {
        // Clean up by removing all observers when the EventBus is deinitialized.
        Task { await removeAllObservers() }
    }

    init() {
        DIGraphShared.shared.logger.debug("SharedEventBus initialized")
    }

    /// Posts an event to all registered observers of its type.
    ///
    /// - Parameter event: The event to be posted.
    /// - Returns: True if the event has been posted to any observers, false otherwise.
    @discardableResult
    func post(_ event: AnyEventRepresentable) async -> Bool {
        let key = event.key
        if let observerList = observers[key], !observerList.isEmpty {
            notificationCenter.post(name: NSNotification.Name(key), object: event)
            return true
        }
        return false
    }

    /// Registers an observer for a specific event type.
    ///
    /// - Parameters:
    ///   - eventType: The type of the event to observe.
    ///   - action: The action to be executed when the event is received.
    func addObserver(_ eventType: String, action: @escaping (AnyEventRepresentable) -> Void) {
        let observer = notificationCenter.addObserver(forName: NSNotification.Name(eventType), object: nil, queue: nil) { notification in
            if let event = notification.object as? AnyEventRepresentable {
                action(event)
            }
        }
        // Store the observer reference for later management.
        if observers[eventType] != nil {
            observers[eventType]?.append(observer)
        } else {
            observers[eventType] = [observer]
        }
    }

    /// Removes all observers from the EventBus.
    ///
    /// This function is used for cleanup or resetting the event handling system.
    func removeAllObservers() async {
        observers.forEach { _, observerList in
            observerList.forEach(notificationCenter.removeObserver)
        }
        observers.removeAll()
    }

    /// Removes all observers for a specific event type.
    ///
    /// - Parameter eventType: The event type for which to remove all observers.
    func removeObserver(for eventType: String) async {
        if let observerList = observers[eventType] {
            for observer in observerList {
                notificationCenter.removeObserver(observer)
            }
            observers[eventType] = nil
        }
    }
}
