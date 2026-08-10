import Foundation

/// Protocol defining the interface for the event bus handler.
public protocol EventBusHandler {
    /// Loads persisted events into the in-memory replay cache.
    func loadEventsFromStorage() async

    /// Registers an observer and replays cached events of the requested type.
    ///
    /// The callback is invoked synchronously on the EventBus delivery task and must return
    /// without blocking on EventBus work, including posts or registry mutations it initiates.
    func addObserver<E: EventRepresentable>(_ eventType: E.Type, action: @escaping (E) -> Void)

    /// Removes all observers registered for the requested event type.
    func removeObserver<E: EventRepresentable>(for eventType: E.Type)

    /// Schedules an event for asynchronous delivery.
    func postEvent<E: EventRepresentable>(_ event: E)

    /// Posts an event and returns after its current observers have been invoked.
    func postEventAndWait<E: EventRepresentable>(_ event: E) async

    /// Removes a previously persisted event. Missing events are ignored.
    func removeFromStorage<E: EventRepresentable>(_ event: E) async
}
