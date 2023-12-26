import Foundation

/// `MemoryStorage` is an actor that encapsulates thread-safe access to in-memory storage
/// of events. It allows storing, appending, retrieving, and removing events associated with specific keys.
actor MemoryStorage {
    /// Storage dictionary to hold arrays of `AnyEventRepresentable` events, keyed by their unique keys.
    private var storage: [String: [AnyEventRepresentable]] = [:]

    /// Appends an event to the storage.
    /// - Parameters:
    ///   - event: The event to append.
    func appendEvent<E: EventRepresentable>(_ event: E) {
        storage[event.key, default: []].append(event)
    }

    /// Stores a collection of events under a specific key.
    /// If events already exist for the key, the new events are appended.
    /// - Parameters:
    ///   - events: The events to store.
    ///   - key: The key under which to store the events.
    func storeEvents(_ events: [AnyEventRepresentable], forKey key: String) {
        if storage[key] != nil {
            storage[key]?.append(contentsOf: events)
        } else {
            storage[key] = events
        }
    }

    /// Retrieves events associated with a given key.
    /// - Parameter key: The key for which to retrieve events.
    /// - Returns: An array of events associated with the key.
    func eventsForKey(_ key: String) -> [AnyEventRepresentable] {
        storage[key] ?? []
    }

    /// Removes all events associated with a given key.
    /// - Parameter key: The key for which to remove all events.
    func removeAllEventsForKey(_ key: String) {
        storage[key] = nil
    }
}
