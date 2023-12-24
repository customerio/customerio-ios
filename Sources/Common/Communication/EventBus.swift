import Foundation

/// Defines the contract for an event bus system.
///
/// Specifies methods for sending events and registering for event notifications.
/// Supports type-safe event handling and scheduler-based execution.
public protocol EventBus: AutoMockable {
    @discardableResult
    func post(_ event: AnyEventRepresentable) async -> Bool
    func addObserver(_ eventType: String, action: @escaping (AnyEventRepresentable) -> Void) async
    func removeAllObservers() async
    func removeObserver(for eventType: String) async
}

/// Defines the contract for an event bus system.
///
/// Specifies methods for sending events and registering for event notifications.
/// Supports type-safe event handling and scheduler-based execution.
actor SharedEventBus: EventBus {
    private var notificationCenter: NotificationCenter = .default
    private var observers: [String: [NSObjectProtocol]] = [:]

    deinit {
        Task { await removeAllObservers() }
    }

    init() {
        DIGraphShared.shared.logger.debug("SharedEventBus initialized")
    }

    @discardableResult
    // Posts an event to the EventBus.
    func post(_ event: AnyEventRepresentable) async -> Bool {
        let key = event.key
        if let observerList = observers[key], !observerList.isEmpty {
            notificationCenter.post(name: NSNotification.Name(key), object: event)
            return true
        }
        return false
    }

    func addObserver(_ eventType: String, action: @escaping (AnyEventRepresentable) -> Void) {
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

    func removeAllObservers() async {
        observers.forEach { _, observerList in
            observerList.forEach(notificationCenter.removeObserver)
        }
        observers.removeAll()
    }

    func removeObserver(for eventType: String) async {
        if let observerList = observers[eventType] {
            for observer in observerList {
                notificationCenter.removeObserver(observer)
            }
            observers[eventType] = nil
        }
    }
}
