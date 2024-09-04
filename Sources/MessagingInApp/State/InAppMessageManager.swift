import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "InAppMessageManager"
// sourcery: InjectSingleton
/// InAppMessageManager is the main class used to interact and manage the InAppMessage state.
/// It is responsible for dispatching actions, subscribing to state changes and fetching the current state.
/// It is also responsible for initializing the store with the required middleware and reducer.
/// It also makes asynchronous calls convenient by wrapping them in non-async methods.
public class InAppMessageManager {
    private let logger: Logger
    private let store: InAppMessageStore

    var state: InAppMessageState {
        get async { await store.state }
    }

    init(logger: Logger, threadUtil: ThreadUtil, logManager: LogManager) {
        // swiftlint:disable todo
        self.logger = logger
        self.store = InAppMessageStore(
            reducer: inAppMessageReducer(logger: logger),
            state: InAppMessageState(),
            // Sequence of middleware is important. The order of middleware is the order they are executed.
            // userAuthenticationMiddleware must be first middleware to ensure user is authenticated before any other action is taken.
            // messageEventCallbacksMiddleware and errorReportingMiddleware must be last to ensure they are executed after all other middlewares.
            middleware: [
                userAuthenticationMiddleware(),
                routeMatchingMiddleware(logger: logger),
                modalMessageDisplayStateMiddleware(logger: logger, threadUtil: threadUtil),
                messageMetricsMiddleware(logger: logger, logManager: logManager),
                messageQueueProcessorMiddleware(logger: logger),
                // TODO: Pass delegate to this middleware once Gist shared instance is removed.
                messageEventCallbacksMiddleware(delegate: nil),
                errorReportingMiddleware(logger: logger)
            ]
        )
        // swiftlint:enable todo
    }

    /// Fetches current state of the InAppMessage store and calls the completion block with result.
    @discardableResult
    func fetchState(_ completion: @escaping (InAppMessageState) -> Void) -> Task<InAppMessageState, Never> {
        Task {
            let currentState = await state
            completion(currentState)
            return currentState
        }
    }

    @discardableResult
    func dispatch(action: InAppMessageAction) -> Task<Void, Never> {
        Task { await store.dispatch(action) }
    }

    @discardableResult
    func unsubscribe(subscriber: InAppMessageStoreSubscriber) -> Task<Void, Never> {
        Task { await store.unsubscribe(subscriber) }
    }

    /// Subscribe to store updates with given subscriber.
    /// The store holds weak reference to the subscriber to avoid retain cycles.
    /// In order to keep the subscriber alive, the caller must keep a strong reference to the subscriber.
    @discardableResult
    func subscribe(subscriber: InAppMessageStoreSubscriber) -> Task<Void, Never> {
        Task { await store.subscribe(subscriber) }
    }

    /// Subscribe to store updates with given subscriber and comparator.
    /// The comparator is used to filter out repeated states.
    /// The store holds weak reference to the subscriber to avoid retain cycles.
    /// In order to keep the subscriber alive, the caller must keep a strong reference to the subscriber.
    /// - Parameters:
    ///   - comparator: Closure that takes two states and returns a boolean indicating whether the states are equal.
    ///   - subscriber: The subscriber to be notified of state changes.
    @discardableResult
    func subscribe(
        comparator: @escaping (InAppMessageState, InAppMessageState) -> Bool,
        subscriber: InAppMessageStoreSubscriber
    ) -> Task<Void, Never> {
        Task { await self.store.subscribe(subscriber, comparator) }
    }

    @discardableResult
    func subscribe<Value>(
        keyPath: KeyPath<InAppMessageState, Value>,
        subscriber: InAppMessageStoreSubscriber
    ) -> Task<Void, Never> where Value: Equatable {
        subscribe(
            comparator: { oldState, newState in
                oldState[keyPath: keyPath] == newState[keyPath: keyPath]
            },
            subscriber: subscriber
        )
    }
}
