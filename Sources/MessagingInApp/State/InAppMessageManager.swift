import CioInternalCommon
import Foundation

protocol InAppMessageManager: AutoMockable {
    var state: InAppMessageState { get async }

    @discardableResult
    func fetchState(_ completion: @escaping (InAppMessageState) -> Void) -> Task<InAppMessageState, Never>

    @discardableResult
    func dispatch(action: InAppMessageAction, completion: (() -> Void)?) -> Task<Void, Never>

    @discardableResult
    func unsubscribe(subscriber: InAppMessageStoreSubscriber) -> Task<Void, Never>

    @discardableResult
    func subscribe(
        comparator: @escaping (InAppMessageState, InAppMessageState) -> Bool,
        subscriber: InAppMessageStoreSubscriber
    ) -> Task<Void, Never>
}

extension InAppMessageManager {
    @discardableResult
    func dispatch(action: InAppMessageAction) -> Task<Void, Never> {
        dispatch(action: action, completion: nil)
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

// sourcery: InjectRegisterShared = "InAppMessageManager"
// sourcery: InjectSingleton
/// InAppMessageManager is the main class used to interact and manage the InAppMessage state.
/// It is responsible for dispatching actions, subscribing to state changes and fetching the current state.
/// It is also responsible for initializing the store with the required middleware and reducer.
/// It also makes asynchronous calls convenient by wrapping them in non-async methods.
class InAppMessageStoreManager: InAppMessageManager {
    private let logger: Logger
    private let store: InAppMessageStore

    var state: InAppMessageState {
        get async { await store.state }
    }

    init(logger: Logger, threadUtil: ThreadUtil, logManager: LogManager, gistDelegate: GistDelegate) {
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
                messageEventCallbacksMiddleware(delegate: gistDelegate),
                errorReportingMiddleware(logger: logger)
            ]
        )
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
    func dispatch(action: InAppMessageAction, completion: (() -> Void)? = nil) -> Task<Void, Never> {
        Task {
            await store.dispatch(action)
            completion?()
        }
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
}
