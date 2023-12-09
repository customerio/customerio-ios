import Combine
import Foundation

/// Defines the contract for an event bus system.
///
/// Specifies methods for sending events and registering for event notifications.
/// Supports type-safe event handling and scheduler-based execution.
public protocol EventTransmittable: AnyObject {
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
