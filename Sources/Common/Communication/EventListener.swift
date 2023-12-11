import Combine
import Foundation

/// Handles subscriptions and broadcasting of events to subscribers.
///
/// Uses Combine's `PassthroughSubject` to emit events and manage subscriptions.
/// Allows for type-safe handling of events and supports execution on specified schedulers.
public final class EventListener {
    private let publisher = PassthroughSubject<any EventRepresentable, Never>()

    func send(_ event: any EventRepresentable) {
        publisher.send(event)
    }

    func registerSubscription<E: EventRepresentable>(action: @escaping (E) -> Void) -> AnyCancellable {
        publisher
            .compactMap { $0 as? E }
            .sink(receiveValue: action)
    }

    func registerSubscription<E: EventRepresentable, S: Scheduler>(scheduler: S, action: @escaping (E) -> Void) -> AnyCancellable {
        publisher
            .receive(on: scheduler)
            .compactMap { $0 as? E }
            .sink(receiveValue: action)
    }
}
