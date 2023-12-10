import Combine
import Foundation

/// Defines the contract for an event bus system.
///
/// Specifies methods for sending events and registering for event notifications.
/// Supports type-safe event handling and scheduler-based execution.
public protocol EventBus: AnyObject {
    /// Sends an event.
    ///
    /// - Parameters:
    ///     - event: An instance of the event that conforms to the `EventRepresentable` protocol.
    func send<E: EventRepresentable>(_ event: E)

    /// Triggers action when EventBus emits an event.
    ///
    /// - Parameters:
    ///     - eventType: Type of an event that triggers the action.
    ///     - action: The action to perform when an event is emitted by EventBus. The  event instance is passed as a parameter to action.
    /// - Returns: A cancellable instance, which needs to be stored as long as action needs to be triggered. Deallocation of the result will unsubscribe from the event and action will not be triggered.
    @discardableResult func onReceive<E: EventRepresentable>(_ eventType: E.Type, perform action: @escaping (E) -> Void) -> AnyCancellable

    /// Triggers action on specific scheduler when EventBus emits an event.
    ///
    /// - Parameters:
    ///     - eventType: Type of an event that triggers the action.
    ///     - scheduler: The scheduler that is used to perform action.
    ///     - action: The action to perform when an event is emitted by EventBus. The  event instance is passed as a parameter to action.
    /// - Returns: A cancellable instance, which needs to be stored as long as action needs to be triggered. Deallocation of the result will unsubscribe from the event and action will not be triggered.
    @discardableResult func onReceive<E: EventRepresentable, S: Scheduler>(_ eventType: E.Type, performOn scheduler: S, action: @escaping (E) -> Void) -> AnyCancellable
}

/// Main interface for sending events and registering listeners.
///
/// Implements `EventTransmittable` protocol, providing methods to send events and register listeners.
/// Uses `EventListenersRegistry` to manage listeners.
// sourcery: InjectRegisterShared = "EventBus"
// sourcery: InjectSingleton
class SharedEventBus: EventBus {
    private var listenersRegistry: EventListenersRegistry

    public init(listenersRegistry: EventListenersRegistry) {
        self.listenersRegistry = listenersRegistry
    }

    public func send<E>(_ event: E) where E: EventRepresentable {
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
