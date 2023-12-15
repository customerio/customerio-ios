import Foundation

/// Defines the contract for an event bus system.
///
/// Specifies methods for sending events and registering for event notifications.
/// Supports type-safe event handling and scheduler-based execution.
public protocol EventBus {
    @discardableResult func post<E: EventRepresentable>(_ event: E, on queue: DispatchQueue?) -> Bool
    func addObserver<E: EventRepresentable>(_ eventType: E.Type, action: @escaping (E) -> Void)
    func removeAllObservers()
    func removeObserver<E: EventRepresentable>(for eventType: E.Type)
}

/// `SharedEventBus` manages the distribution of events to registered observers.
/// It uses the NotificationCenter for event delivery and manages observer lifecycles.
// sourcery: InjectRegisterShared = "EventBus"
// sourcery: InjectSingleton
public class SharedEventBus: EventBus {
    private var notificationCenter: NotificationCenter = .default
    private var observers: [String: [NSObjectProtocol]] = [:]
    private let queue = DispatchQueue(label: "com.eventbus.shared")

    deinit {
        removeAllObservers()
    }

    init() {
        DIGraphShared.shared.logger.debug("SharedEventBus initialized")
    }

    /// Posts an event to the EventBus.
    /// - Parameters:
    ///   - event: The event to be posted.
    ///   - queue: An optional DispatchQueue on which to post the event. If nil, uses the current queue.
    /// - Returns: Boolean indicating if there were any observers for the event.
    @discardableResult
    public func post<E>(_ event: E, on queue: DispatchQueue? = nil) -> Bool where E: EventRepresentable {
        var hasObservers = false
        self.queue.sync {
            let key = E.key
            if let observerList = self.observers[key], !observerList.isEmpty {
                hasObservers = true
                let postAction = {
                    self.notificationCenter.post(name: NSNotification.Name(E.key), object: event)
                }

                // Posts the event asynchronously on the provided queue or immediately if no queue is provided.
                if let queue = queue {
                    queue.async(execute: postAction)
                } else {
                    postAction()
                }
            }
        }
        return hasObservers
    }

    /// Adds an observer for a specific event type.
    /// - Parameters:
    ///   - eventType: The event type to observe.
    ///   - action: The action to execute when the event is observed.
    public func addObserver<E: EventRepresentable>(_ eventType: E.Type, action: @escaping (E) -> Void) {
        queue.sync {
            let key = E.key
            let observer = notificationCenter.addObserver(forName: NSNotification.Name(key), object: nil, queue: nil) { notification in
                if let event = notification.object as? E {
                    action(event)
                }
            }
            if observers[key] != nil {
                observers[key]?.append(observer)
            } else {
                observers[key] = [observer]
            }
        }
    }

    /// Removes all observers from the EventBus.
    /// This is typically used for cleanup or when resetting the event handling system.
    public func removeAllObservers() {
        queue.sync {
            observers.forEach { _, observerList in
                observerList.forEach { observer in
                    notificationCenter.removeObserver(observer)
                }
            }
            observers.removeAll()
        }
    }

    /// Removes all observers for a specific event type.
    /// - Parameter eventType: The event type for which to remove observers.
    public func removeObserver<E: EventRepresentable>(for eventType: E.Type) {
        queue.sync {
            let key = E.key
            if let observerList = observers[key] {
                for observer in observerList {
                    notificationCenter.removeObserver(observer)
                }
                observers[key] = nil
            }
        }
    }
}
