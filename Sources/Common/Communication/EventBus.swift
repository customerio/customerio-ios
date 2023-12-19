import Foundation

/// Defines the contract for an event bus system.
///
/// Specifies methods for sending events and registering for event notifications.
/// Supports type-safe event handling and scheduler-based execution.
public protocol EventBus: AutoMockable {
    @discardableResult
    func post(_ event: AnyEventRepresentable, on queue: DispatchQueue?) -> Bool
    func addObserver(_ eventType: String, action: @escaping (AnyEventRepresentable) -> Void)
    func removeAllObservers()
    func removeObserver(for eventType: String)
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
    public func post(_ event: AnyEventRepresentable, on queue: DispatchQueue? = nil) -> Bool {
        var hasObservers = false
        self.queue.sync {
            let key = event.key
            if let observerList = self.observers[key], !observerList.isEmpty {
                hasObservers = true
                let postAction = {
                    self.notificationCenter.post(name: NSNotification.Name(key), object: event)
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
    public func addObserver(_ eventType: String, action: @escaping (AnyEventRepresentable) -> Void) {
        queue.sync {
            let observer = notificationCenter.addObserver(forName: NSNotification.Name(eventType), object: nil, queue: nil) { notification in
                if let event = notification.object as? AnyEventRepresentable {
                    action(event)
                }
            }
            if observers[eventType] != nil {
                observers[eventType]?.append(observer)
            } else {
                observers[eventType] = [observer]
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
    public func removeObserver(for eventType: String) {
        queue.sync {
            if let observerList = observers[eventType] {
                for observer in observerList {
                    notificationCenter.removeObserver(observer)
                }
                observers[eventType] = nil
            }
        }
    }
}
