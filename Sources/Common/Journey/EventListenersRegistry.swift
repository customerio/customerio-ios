import Foundation

/// Manages `EventListener` instances for different event types.
///
/// Stores listeners in a dictionary keyed by the event type's description.
/// This allows for efficient retrieval and management of listeners based on the type of event.
final class EventListenersRegistry {
    private var listeners = [String: EventListener]()

    // Buffer to store events that are emitted before any listener is registered.
    private var eventBuffer = [String: [EventRepresentable]]()

    // DispatchQueue for thread-safe access to `listeners` and `eventBuffer`.
    private let queue = DispatchQueue(label: "event.bus.EventListenersRegistry", attributes: .concurrent)

    /// Buffers an event if there are no listeners for its type.
    /// - Parameter event: The event to be buffered.
    func bufferEvent<E: EventRepresentable>(_ event: E) {
        let key = String(describing: E.self)
        queue.async(flags: .barrier) {
            if self.listeners[key] == nil {
                self.eventBuffer[key, default: []].append(event)
            }
        }
    }

    /// Replays buffered events for a given event type to a specific listener.
    /// - Parameters:
    ///   - key: The event type's key.
    ///   - listener: The listener to receive the replayed events.
    func replayBufferedEvents(for key: String, to listener: EventListener) {
        queue.async {
            guard let bufferedEvents = self.eventBuffer[key] else { return }
            bufferedEvents.forEach { listener.send($0) }
            self.eventBuffer[key] = nil // Clear the buffer after replaying
        }
    }

    /// Retrieves or creates a listener for a given event type.
    /// - Parameter eventType: The type of the event.
    /// - Returns: An `EventListener` for the given event type.
    func getOrCreateListener<E: EventRepresentable>(forEventType eventType: E.Type) -> EventListener {
        let key = String(describing: eventType)
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
        let key = String(describing: eventType)
        return queue.sync {
            return self.listeners[key]
        }
    }
}
