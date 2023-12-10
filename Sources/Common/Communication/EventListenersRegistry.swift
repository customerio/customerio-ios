import Foundation

protocol EventListenersRegistry {
    func bufferEvent<E: EventRepresentable>(_ event: E) where E: Equatable
    func replayBufferedEvents(for key: String, to listener: EventListener)
    func getOrCreateListener<E: EventRepresentable>(forEventType eventType: E.Type) -> EventListener
    func getListener<E: EventRepresentable>(forEventType eventType: E.Type) -> EventListener?
}

/// Manages `EventListener` instances for different event types.
///
/// Stores listeners in a dictionary keyed by the event type's description.
/// This allows for efficient retrieval and management of listeners based on the type of event.
// sourcery: InjectRegisterShared = "EventListenersRegistry"
final class EventListenersManager: EventListenersRegistry {
    private var listeners = [String: EventListener]()
    // Buffer to store events that are emitted before any listener is registered.
    private var eventBuffer = [String: [any EventRepresentable]]()

    // DispatchQueue for thread-safe access to `listeners` and `eventBuffer`.
    private let queue = DispatchQueue(label: "event.bus.EventListenersRegistry", attributes: .concurrent)

    private let eventStorage: EventStorage // Manages file storage for events.

    init(eventStorage: EventStorage) {
        self.eventStorage = eventStorage
    }

    /// Buffers an event if there are no listeners for its type.
    /// - Parameter event: The event to be buffered.
    func bufferEvent<E: EventRepresentable>(_ event: E) where E: Equatable {
        let key = String(describing: E.self)
        queue.async(flags: .barrier) {
            // Check if the last buffered event is the same as the current one.
            if let lastEvent = self.eventBuffer[key]?.last as? E, lastEvent != event {
                // Add to in-memory buffer.
                self.eventBuffer[key, default: []].append(event)

                // Serialize and store the event to file.
                do {
                    try self.eventStorage.store(event: event, forKey: key)
                } catch {
                    print("Error storing event: \(error)")
                }
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

            // Dispatch each buffered event to the listener.
            bufferedEvents.forEach { listener.send($0) }

            // Remove events from file storage after replaying to at least one listener.
            // Handle any errors that might occur during this process.
            do {
                try self.eventStorage.clearEvent(forKey: key)
            } catch {
                // Handle or log the error appropriately.
                print("Error clearing bus event from storage: \(error)")
            }
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
