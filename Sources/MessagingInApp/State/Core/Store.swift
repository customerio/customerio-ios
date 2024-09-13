// swiftlint:disable:next file_header
//
//  Store.swift
//  ReSwift
//
//  Created by Benjamin Encz on 11/11/15.
//  Copyright © 2015 ReSwift Community. All rights reserved.
//
//  Modifications made:
//  - Replaced Action with InAppMessageAction from Customer.io.
//  - Constrained State to Equatable to simplify state comparison as InAppMessageState is Equatable.
//  - Updated visibility to internal to prevent exposing non-public types.
//  - Updated initializer to require non-optional initial State to avoid dispatching dummy init action.
//  - Removed subscriptionsAutomaticallySkipRepeats as it will always be true.
//  - Simplified subscription handling by removing unused subscription options.
//  - Removed unused functions.
//

/**
 This class is the default implementation of the `StoreType` protocol. You will use this store in most
 of your applications. You shouldn't need to implement your own store.
 You initialize the store with a reducer and an initial application state. If your app has multiple
 reducers you can combine them by initializing a `MainReducer` with all of your reducers as an
 argument.
 */
class Store<State: Equatable> {
    typealias SubscriptionType = SubscriptionBox<State>

    public private(set) var state: State! {
        didSet {
            subscriptions.forEach {
                if $0.subscriber == nil {
                    subscriptions.remove($0)
                } else {
                    $0.newValues(oldState: oldValue, newState: state)
                }
            }
        }
    }

    public lazy var dispatchFunction: DispatchFunction! = createDispatchFunction()

    private var reducer: Reducer<State>

    var subscriptions: Set<SubscriptionType> = []

    private var isDispatching = Synchronized<Bool>(false)

    public var middleware: [Middleware<State>] {
        didSet {
            dispatchFunction = createDispatchFunction()
        }
    }

    /// Initializes the store with a reducer, an initial state and a list of middleware.
    ///
    /// Middleware is applied in the order in which it is passed into this constructor.
    ///
    /// - parameter reducer: Main reducer that processes incoming actions.
    /// - parameter state: Initial state, if any. Can be `nil` and will be
    ///   provided by the reducer in that case.
    /// - parameter middleware: Ordered list of action pre-processors, acting
    ///   before the root reducer.
    /// - parameter automaticallySkipsRepeats: If `true`, the store will attempt
    ///   to skip idempotent state updates when a subscriber's state type
    ///   implements `Equatable`. Defaults to `true`.
    public required init(
        reducer: @escaping Reducer<State>,
        state: State,
        middleware: [Middleware<State>] = []
    ) {
        self.reducer = reducer
        self.middleware = middleware
        self.state = state
    }

    private func createDispatchFunction() -> DispatchFunction! {
        // Wrap the dispatch function with all middlewares
        middleware
            .reversed()
            .reduce({ [unowned self] action in
                    _defaultDispatch(action: action) }, { dispatchFunction, middleware in
                    // If the store get's deinitialized before the middleware is complete; drop
                    // the action without dispatching.
                    let dispatch: (InAppMessageAction) -> Void = { [weak self] in self?.dispatch($0) }
                    let getState: () -> State? = { [weak self] in self?.state }
                    return middleware(dispatch, getState)(dispatchFunction)
                }
            )
    }

    private func _subscribe<S: StoreSubscriber>(
        _ subscriber: S,
        originalSubscription: Subscription<State>,
        transformedSubscription: Subscription<State>?
    ) where S.StoreSubscriberStateType == State {
        let subscriptionBox = self.subscriptionBox(
            originalSubscription: originalSubscription,
            transformedSubscription: transformedSubscription,
            subscriber: subscriber
        )

        subscriptions.update(with: subscriptionBox)

        if let state = state {
            originalSubscription.newValues(oldState: nil, newState: state)
        }
    }

    public func subscribe<S: StoreSubscriber>(
        _ subscriber: S,
        transform: ((Subscription<State>) -> Subscription<State>) = { $0.skipRepeats() }
    ) where S.StoreSubscriberStateType == State {
        let originalSubscription = Subscription<State>()

        _subscribe(
            subscriber,
            originalSubscription: originalSubscription,
            transformedSubscription: transform(originalSubscription)
        )
    }

    func subscriptionBox<T>(
        originalSubscription: Subscription<State>,
        transformedSubscription: Subscription<T>?,
        subscriber: AnyStoreSubscriber
    ) -> SubscriptionBox<State> {
        SubscriptionBox(
            originalSubscription: originalSubscription,
            transformedSubscription: transformedSubscription,
            subscriber: subscriber
        )
    }

    func unsubscribe(_ subscriber: AnyStoreSubscriber) {
        #if swift(>=5.0)
        if let index = subscriptions.firstIndex(where: { $0.subscriber === subscriber }) {
            subscriptions.remove(at: index)
        }
        #else
        if let index = subscriptions.index(where: { $0.subscriber === subscriber }) {
            subscriptions.remove(at: index)
        }
        #endif
    }

    // swiftlint:disable:next identifier_name
    func _defaultDispatch(action: InAppMessageAction) {
        guard !isDispatching.value else {
            raiseFatalError(
                "ReSwift:ConcurrentMutationError- Action has been dispatched while" +
                    " a previous action is being processed. A reducer" +
                    " is dispatching an action, or ReSwift is used in a concurrent context" +
                    " (e.g. from multiple threads). Action: \(action)"
            )
        }

        isDispatching.value { $0 = true }
        let newState = reducer(action, state)
        isDispatching.value { $0 = false }

        state = newState
    }

    open func dispatch(_ action: InAppMessageAction) {
        dispatchFunction(action)
    }
}
