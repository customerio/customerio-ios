import Combine
import Foundation

// sourcery: InjectRegisterShared = "EventBusHandler"
// sourcery: InjectSingleton
public class EventBusHandler {
    private let eventBus: EventBus
    private let eventStorage: EventStorage
    private var memoryStorage: [String: [AnyEventRepresentable]] = [:]
    private let logger: Logger

    public init(eventBus: EventBus, eventStorage: EventStorage, logger: Logger) {
        self.eventBus = eventBus
        self.eventStorage = eventStorage
        self.logger = logger
        Task { await loadEventsFromStorage() }
    }

    private func loadEventsFromStorage() async {
        for eventType in EventTypesRegistry.allEventTypes() {
            do {
                let key = eventType.key
                let events: [AnyEventRepresentable] = try await eventStorage.loadEvents(ofType: key)
                memoryStorage[key, default: []].append(contentsOf: events)
            } catch {
                logger.debug("Error loading events for \(eventType): \(error)")
            }
        }
    }

    public func addObserver<E: EventRepresentable>(_ eventType: E.Type, action: @escaping (E) -> Void) {
        logger.debug("EventBusHandler: Adding observer for event type - \(eventType)")

        let adaptedAction: (AnyEventRepresentable) -> Void = { event in
            if let specificEvent = event as? E {
                action(specificEvent)
            } else {
                self.logger.debug("Error: Event type did not match")
            }
        }

        Task { await eventBus.addObserver(eventType.key, action: adaptedAction) }
        replayEvents(forType: eventType)
    }

    public func removeObserver<E: EventRepresentable>(for eventType: E.Type) {
        Task { await eventBus.removeObserver(for: E.key) }
    }

    private func replayEvents<E: EventRepresentable>(forType eventType: E.Type) {
        let key = eventType.key
        if let storedEvents = memoryStorage[key] as? [E] {
            storedEvents.forEach { event in
                logger.debug("EventBusHandler: Replaying event type - \(event)")
                Task {
                    let isSent = await eventBus.post(event)
                    if isSent {
                        await removeFromStorage(event)
                    }
                }
            }
        }
    }

    public func postEvent<E: EventRepresentable>(_ event: E) {
        logger.debug("EventBusHandler: Posting event - \(event)")
        Task {
            let hasObservers = await eventBus.post(event)
            memoryStorage[event.key, default: []].append(event)
            if !hasObservers {
                logger.debug("EventBusHandler: Storing event in memory - \(event)")
                await storeEvent(event)
            }
        }
    }

    private func storeEvent<E: EventRepresentable>(_ event: E) async {
        do {
            try await eventStorage.store(event: event)
        } catch {
            logger.debug("Error storing event: \(error)")
        }
    }

    public func removeFromStorage<E: EventRepresentable>(_ event: E) async {
        await eventStorage.remove(ofType: event.key, withStorageId: event.storageId)
    }
}
