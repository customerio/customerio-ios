import Combine
import Foundation

/// Manages the handling of events through an event bus and coordinates with event storage.
/// It handles both in-memory and file-based storage of events.
// sourcery: InjectRegisterShared = "EventBusHandler"
// sourcery: InjectSingleton
public class EventBusHandler {
    private let eventBus: EventBus
    private let eventStorage: EventStorage
    private var memoryStorage: [String: [AnyEventRepresentable]] = [:]
    private var logger: Logger = DIGraphShared.shared.logger

    /// Initializes the EventBusHandler with an EventBus and EventStorage.
    /// Automatically loads events from file-based storage into in-memory storage upon initialization.
    public init(eventBus: EventBus, eventStorage: EventStorage) {
        self.eventBus = eventBus
        self.eventStorage = eventStorage
        loadEventsFromStorage()
    }

    /// Loads events from file-based persistent storage into in-memory storage for each registered event type.
    /// This facilitates quick access and ensures events can be replayed to late subscribers.
    private func loadEventsFromStorage() {
        EventTypesRegistry.allEventTypes().forEach { eventType in
            do {
                let key = eventType.key
                let events: [AnyEventRepresentable] = try eventStorage.loadEvents(ofType: key)
                memoryStorage[key, default: []].append(contentsOf: events)
            } catch {
                // Handle the error, for example, log it or take some recovery actions
                logger.debug("Error loading events for \(eventType): \(error)")
            }
        }
    }

    /// Adds an observer for a specific event type.
    /// Replays any in-memory stored events of that type to the new observer.
    public func addObserver<E: EventRepresentable>(_ eventType: E.Type, action: @escaping (E) -> Void) {
        logger.debug("EventBusHandler: Adding observer for event type - \(eventType)")

        let adaptedAction: (AnyEventRepresentable) -> Void = { event in
            if let specificEvent = event as? E {
                action(specificEvent)
            } else {
                // Handle the error or log it. The event type did not match.
                self.logger.debug("Error: Event type did not match")
            }
        }

        eventBus.addObserver(eventType.key, action: adaptedAction)
        replayEvents(forType: eventType)
    }

    public func removeObserver<E: EventRepresentable>(for eventType: E.Type) {
        eventBus.removeObserver(for: E.key)
    }

    /// Replays events of a specific type from in-memory storage to the newly added observer.
    /// Events that are successfully sent to an observer are removed from file-based storage.
    public func replayEvents<E: EventRepresentable>(forType eventType: E.Type) {
        let key = eventType.key
        if let storedEvents = memoryStorage[key] as? [E] {
            storedEvents.forEach {
                logger.debug("EventBusHandler: Replaying event type - \($0)")
                let isSent = eventBus.post($0, on: nil)
                if isSent {
                    removeFromStorage($0)
                }
            }
        }
    }

    /// Posts an event to the EventBus.
    /// If there are no observers, the event is stored in file-based storage so we don't lose it.
    /// Regardless of being sent, the event is temporarily stored in in-memory storage for replay to new observers.
    public func postEvent<E: EventRepresentable>(_ event: E) {
        print("EventBusHandler: Posting event - \(event)")
        let hasObservers = eventBus.post(event, on: nil)
        memoryStorage[event.key, default: []].append(event)
        if !hasObservers {
            logger.debug("EventBusHandler: Storing event in memory - \(event)")
            storeEvent(event)
        }
    }

    /// Stores an event in file-based persistent storage.
    /// This method is used when an event is posted but no observers are currently registered.
    private func storeEvent<E: EventRepresentable>(_ event: E) {
        do {
            try eventStorage.store(event: event)
        } catch {
            logger.debug("Error storing event: \(error)")
        }
    }

    /// Removes an event from file-based storage.
    /// Used when an event from in-memory storage has been successfully sent to all observers.
    public func removeFromStorage<E: EventRepresentable>(_ event: E) {
        do {
            try eventStorage.remove(ofType: event.key, withStorageId: event.storageId)
        } catch {
            logger.debug("Error removing event from storage: \(error)")
        }
    }
}
