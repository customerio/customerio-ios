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
    @discardableResult func send<E: EventRepresentable>(_ event: E) -> Bool

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

/// `SharedEventBus` is a centralized component that manages event distribution in an application.
/// It allows for the sending of events and the registration of listeners to handle specific event types.
///
/// The EventBus follows a publish-subscribe pattern, enabling loose coupling between event producers and consumers.
///
/// Usage:
/// - To send an event: `eventBus.send(myEvent)`
/// - To listen for an event: `eventBus.onReceive(MyEventType.self) { event in /* handle event */ }`
///
/// Important:
/// - `SharedEventBus` emits `NewSubscriptionEvent` when a new listener subscribes to a specific event type.
///   This allows other parts of the system to react to changes in event listeners.
/// - Be cautious when subscribing to `NewSubscriptionEvent` within its own handler.
///   Creating a new subscription to `NewSubscriptionEvent` in its handler can lead to unintended recursion
///   and should be avoided to prevent potential infinite loops.
///
/// Thread Safety:
/// - `SharedEventBus` is designed to be thread-safe. It ensures that events are sent and listeners are registered
///   in a thread-safe manner.
///
/// Example:
/// ```
/// let eventBus = SharedEventBus(listenersRegistry: ...)
/// eventBus.onReceive(ProfileIdentifiedEvent.self) { event in
///     print("Received ProfileIdentifiedEvent with identifier: \(event.identifier)")
/// }
/// eventBus.send(ProfileIdentifiedEvent(identifier: "user123"))
/// ```

// sourcery: InjectRegisterShared = "EventBus"
// sourcery: InjectSingleton
public class SharedEventBus: EventBus {
    private var listenersRegistry: EventListenersRegistry

    /// Initializes a new instance of `SharedEventBus`.
    ///
    /// - Parameter listenersRegistry: The registry used to manage listeners for different event types.
    public init(listenersRegistry: EventListenersRegistry) {
        self.listenersRegistry = listenersRegistry
    }

    /// Sends an event to the corresponding listeners.
    ///
    /// - Parameter event: The event to be sent. Must conform to `EventRepresentable`.
    @discardableResult public func send<E>(_ event: E) -> Bool where E: EventRepresentable {
        guard let listener = listenersRegistry.getListener(forEventType: E.self) else {
            return false
        }
        listener.send(event)
        return true
    }

    /// Registers a listener for a specific event type and performs the provided action when that event is emitted.
    ///
    /// - Parameters:
    ///   - eventType: The type of event to listen for.
    ///   - action: The action to perform when an event of the specified type is emitted.
    /// - Returns: A cancellable instance used to unsubscribe from the event.
    @discardableResult
    public func onReceive<E: EventRepresentable>(_ eventType: E.Type, perform action: @escaping (E) -> Void) -> AnyCancellable {
        subscribeAndNotify(eventType: eventType, action: action)
    }

    /// Registers a listener for a specific event type on a specified scheduler and performs the provided action when that event is emitted.
    ///
    /// - Parameters:
    ///   - eventType: The type of event to listen for.
    ///   - scheduler: The scheduler on which to perform the action.
    ///   - action: The action to perform when an event of the specified type is emitted.
    /// - Returns: A cancellable instance used to unsubscribe from the event.
    @discardableResult
    public func onReceive<E: EventRepresentable, S: Scheduler>(_ eventType: E.Type, performOn scheduler: S, action: @escaping (E) -> Void) -> AnyCancellable {
        subscribeAndNotify(eventType: eventType, scheduler: scheduler, action: action)
    }

    /// A helper method to manage the subscription and notify about new subscriptions.
    ///
    /// - Parameters:
    ///   - eventType: The type of event to listen for.
    ///   - scheduler: An optional scheduler on which to perform the action.
    ///   - action: The action to perform when an event of the specified type is emitted.
    /// - Returns: A cancellable instance used to unsubscribe from the event.
    private func subscribeAndNotify<E: EventRepresentable>(
        eventType: E.Type,
        scheduler: (any Scheduler)? = nil, // Optional scheduler
        action: @escaping (E) -> Void
    ) -> AnyCancellable {
        let isNewListener = !listenersRegistry.hasListener(forEventType: E.self)
        let listener = listenersRegistry.getOrCreateListener(forEventType: E.self)

        let subscription: AnyCancellable
        if let scheduler = scheduler {
            subscription = listener.registerSubscription(scheduler: scheduler, action: action)
        } else {
            subscription = listener.registerSubscription(action: action)
        }

        // Prevent emitting NewSubscriptionEvent for its own subscriptions
        if isNewListener, eventType != NewSubscriptionEvent.self {
            // Notify about the new subscription
            send(NewSubscriptionEvent(subscribedEventType: E.self))
        }

        return subscription
    }
}
