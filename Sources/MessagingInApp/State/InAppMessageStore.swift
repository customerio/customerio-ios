import Foundation
import ReSwift

/// Store class wrapped as actor to maintain consistency and thread safety
/// This also decouples store callers from ReSwift dependency by exposing only required methods
actor InAppMessageStore {
    private let store: Store<InAppMessageState>

    var state: InAppMessageState { store.state }

    init(
        reducer: @escaping Reducer<InAppMessageState>,
        state: InAppMessageState?,
        middleware: [Middleware<InAppMessageState>],
        automaticallySkipsRepeats: Bool = true
    ) {
        self.store = Store(
            reducer: reducer,
            state: state,
            middleware: middleware,
            automaticallySkipsRepeats: automaticallySkipsRepeats
        )
    }

    func dispatch(_ action: InAppMessageAction) {
        store.dispatch(action)
    }

    func unsubscribe(_ subscriber: InAppMessageStoreSubscriber) {
        store.unsubscribe(subscriber)
    }

    func subscribe(_ subscriber: InAppMessageStoreSubscriber) {
        store.subscribe(subscriber)
    }

    /// Subscribe to store with conditionally skipping repeated states filtered by comparator
    func subscribe(
        _ subscriber: InAppMessageStoreSubscriber,
        _ comparator: @escaping (InAppMessageState, InAppMessageState) -> Bool
    ) {
        store.subscribe(subscriber) { subscription in
            subscription.skip(when: comparator)
        }
    }
}
