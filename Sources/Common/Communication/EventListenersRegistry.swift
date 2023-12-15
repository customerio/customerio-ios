import Foundation

public protocol EventListenersRegistry {
    func getOrCreateListener<E: EventRepresentable>(forEventType eventType: E.Type) -> EventListener
    func getListener<E: EventRepresentable>(forEventType eventType: E.Type) -> EventListener?
    func hasListener<E: EventRepresentable>(forEventType eventType: E.Type) -> Bool
}

/// Manages `EventListener` instances for different event types.
///
/// Stores listeners in a dictionary keyed by the event type's description.
/// This allows for efficient retrieval and management of listeners based on the type of event.
// sourcery: InjectRegisterShared = "EventListenersRegistry"
final class EventListenersManager: EventListenersRegistry {
    private var listeners = [String: EventListener]()

    // DispatchQueue for thread-safe access to `listeners` and `eventBuffer`.
    private let queue = DispatchQueue(label: "event.bus.EventListenersRegistry", attributes: .concurrent)

    init() {}

    /// Retrieves or creates a listener for a given event type.
    /// - Parameter eventType: The type of the event.
    /// - Returns: An `EventListener` for the given event type.
    func getOrCreateListener<E: EventRepresentable>(forEventType eventType: E.Type) -> EventListener {
        let key = eventType.key
        return queue.sync {
            if let existingListener = self.listeners[key] {
                return existingListener
            } else {
                let newListener = EventListener()
                self.listeners[key] = newListener
                return newListener
            }
        }
    }

    /// Retrieves a listener for a given event type, if one exists.
    /// - Parameter eventType: The type of the event.
    /// - Returns: An optional `EventListener` for the given event type.
    func getListener<E: EventRepresentable>(forEventType eventType: E.Type) -> EventListener? {
        let key = eventType.key
        return queue.sync {
            return self.listeners[key]
        }
    }

    func hasListener<E: EventRepresentable>(forEventType eventType: E.Type) -> Bool {
        let key = eventType.key
        return listeners[key] != nil
    }
}
