import Combine
import Foundation

public class EventBusHandler {
    private let eventBus: EventBus
    private let eventStorage: EventStorage

    public init(eventBus: EventBus, eventStorage: EventStorage) {
        self.eventBus = eventBus
        self.eventStorage = eventStorage
    }

    public func send<E>(_ event: E) where E: EventRepresentable {
        if eventBus.send(event) == false {
            let key = event.key
            do {
                try eventStorage.store(event: event, forKey: key)
            } catch {
                print("Error storing event: \(error)")
            }
        }
    }

    @discardableResult
    public func onReceive<E: EventRepresentable>(_ eventType: E.Type, perform action: @escaping (E) -> Void) -> AnyCancellable {
        subscribeAndReplay(eventType: eventType, action: action)
    }

    @discardableResult
    public func onReceive<E: EventRepresentable, S: Scheduler>(_ eventType: E.Type, performOn scheduler: S, action: @escaping (E) -> Void) -> AnyCancellable {
        subscribeAndReplay(eventType: eventType, scheduler: scheduler, action: action)
    }

    private func subscribeAndReplay<E: EventRepresentable>(
        eventType: E.Type,
        scheduler: (any Scheduler)? = nil, // Optional scheduler
        action: @escaping (E) -> Void
    ) -> AnyCancellable {
        let listener = eventBus.listenersRegistry.getOrCreateListener(forEventType: E.self)

        let subscription: AnyCancellable
        if let scheduler = scheduler {
            subscription = listener.registerSubscription(scheduler: scheduler, action: action)
        } else {
            subscription = listener.registerSubscription(action: action)
        }

        let key = String(describing: E.self)

        loadAndSendStoredEvents(ofType: E.self, to: listener)

        return subscription
    }

    /// Generic method to load and send stored events of a specific type.
    /// - Parameter eventType: The type of event to load and send.
    private func loadAndSendStoredEvents<E: EventRepresentable>(ofType eventType: E.Type, to listener: EventListener) {
        do {
            let key = eventType.key
            let storedEvents: [E] = try eventStorage.loadAllEvents(ofType: eventType, withKey: key)
            storedEvents.forEach { eventBus.send($0) }
        } catch {
            // TODO: handle the error
        }
    }
}
