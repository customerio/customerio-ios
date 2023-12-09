import Combine
import Foundation

/// Main interface for sending events and registering listeners.
///
/// Implements `EventTransmittable` protocol, providing methods to send events and register listeners.
/// Uses `EventListenersRegistry` to manage listeners.
class EventBus: EventTransmittable {
    private var listenersRegistry = EventListenersRegistry()

    public let id: String

    public init(id: String = UUID().uuidString) {
        self.id = id
    }

    public func send<E>(_ event: E) where E: EventRepresentable {
        let key = String(describing: E.self)
        if let listener = listenersRegistry.getListener(forEventType: E.self) {
            listener.send(event)
        } else {
            listenersRegistry.bufferEvent(event) // Buffer the event
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
        let listener = listenersRegistry.getOrCreateListener(forEventType: E.self)

        let subscription: AnyCancellable
        if let scheduler = scheduler {
            subscription = listener.registerSubscription(scheduler: scheduler, action: action)
        } else {
            subscription = listener.registerSubscription(action: action)
        }

        let key = String(describing: E.self)
        listenersRegistry.replayBufferedEvents(for: key, to: listener)

        return subscription
    }
}
