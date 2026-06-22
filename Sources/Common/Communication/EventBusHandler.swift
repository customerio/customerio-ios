import Foundation

/// Protocol defining the interface for the event bus handler.
public protocol EventBusHandler {
    func loadEventsFromStorage() async
    func addObserver<E: EventRepresentable>(_ eventType: E.Type, action: @escaping (E) -> Void)
    func removeObserver<E: EventRepresentable>(for eventType: E.Type)
    func postEvent<E: EventRepresentable>(_ event: E)
    func postEventAndWait<E: EventRepresentable>(_ event: E) async
    func removeFromStorage<E: EventRepresentable>(_ event: E) async
}
