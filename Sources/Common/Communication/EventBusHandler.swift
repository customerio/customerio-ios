import Combine
import Foundation

// sourcery: InjectRegisterShared = "EventBusHandler"
// sourcery: InjectSingleton
public class EventBusHandler {
    private let eventBus: EventBus
    private let eventStorage: EventStorage
    private var memoryStorage: [String: [any EventRepresentable]] = [:]

    public init(eventBus: EventBus, eventStorage: EventStorage) {
        self.eventBus = eventBus
        self.eventStorage = eventStorage
        loadEventsFromStorage()
    }

    private func loadEventsFromStorage() {
        EventTypesRegistry.allEventTypes().forEach { eventType in
            do {
                let key = eventType.key
                let events: [any EventRepresentable] = try eventStorage.loadAllEvents(ofType: eventType, withKey: key)
                memoryStorage[key, default: []].append(contentsOf: events)
            } catch {
                // Handle the error, for example, log it or take some recovery actions
                print("Error loading events for \(eventType): \(error)")
            }
        }
    }

    public func addObserver<E: EventRepresentable>(_ eventType: E.Type, action: @escaping (E) -> Void) {
        eventBus.addObserver(eventType, action: action)
        replayEvents(forType: eventType)
    }

    private func replayEvents<E: EventRepresentable>(forType eventType: E.Type) {
        let key = eventType.key
        if let storedEvents = memoryStorage[key] as? [E] {
            storedEvents.forEach { eventBus.post($0, on: nil) }
        }
    }

    public func postEvent<E: EventRepresentable>(_ event: E) {
        let hasObservers = eventBus.post(event, on: nil)
        if !hasObservers {
            storeEvent(event)
        } else {
            removeFromStorage(event)
        }
    }

    private func storeEvent<E: EventRepresentable>(_ event: E) {
        let key = event.key
        memoryStorage[key, default: []].append(event)
        do {
            try eventStorage.store(event: event, forKey: key)
        } catch {
            print("Error storing event: \(error)")
        }
    }

    private func removeFromStorage<E: EventRepresentable>(_ event: E) {
        let key = event.key
        do {
            try eventStorage.remove(forKey: key)
        } catch {
            print("Error removing event from storage: \(error)")
        }
    }
}
