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

                if let queue = queue {
                    queue.async(execute: postAction)
                } else {
                    postAction()
                }
            }
        }
        return hasObservers
    }

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
