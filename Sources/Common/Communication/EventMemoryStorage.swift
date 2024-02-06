import Foundation

public protocol EventCache: AutoMockable {
    func addEvent(event: AnyEventRepresentable) async
    func storeEvents(_ events: [AnyEventRepresentable], forKey key: String) async
    func getEvent(_ key: String) async -> [AnyEventRepresentable]
    func removeAllEventsForKey(_ key: String) async
}

// swiftlint:disable orphaned_doc_comment
/// `EventMemoryStorage` is an actor that encapsulates thread-safe access to in-memory storage
/// of events. It allows storing, appending, retrieving, and removing events associated with specific keys.
// sourcery: InjectRegisterShared = "EventCache"
// sourcery: InjectSingleton
// swiftlint:enable orphaned_doc_comment
actor EventCacheManager: EventCache {
    /// Storage dictionary to hold arrays of `AnyEventRepresentable` events, keyed by their unique keys.
    private var storage: [String: RingBuffer<AnyEventRepresentable>] = [:]
    private let maxEventsPerType: Int = 100

    /// Appends an event to the storage.
    /// - Parameters:
    ///   - event: The event to append.
    func addEvent(event: AnyEventRepresentable) {
        storeEvents([event], forKey: event.key)
    }

    /// Stores a collection of events under a specific key.
    /// If events already exist for the key, the new events are appended.
    /// - Parameters:
    ///   - events: The events to store.
    ///   - key: The key under which to store the events.
    func storeEvents(_ events: [AnyEventRepresentable], forKey key: String) {
        if storage[key] == nil {
            storage[key] = RingBuffer(capacity: maxEventsPerType)
        }
        storage[key]?.enqueue(contentsOf: events)
    }

    /// Retrieves events associated with a given key.
    /// - Parameter key: The key for which to retrieve events.
    /// - Returns: An array of events associated with the key.
    func getEvent(_ key: String) -> [AnyEventRepresentable] {
        storage[key]?.toArray() ?? []
    }

    /// Removes all events associated with a given key.
    /// - Parameter key: The key for which to remove all events.
    func removeAllEventsForKey(_ key: String) {
        storage[key] = nil
    }
}
