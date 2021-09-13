import Foundation

@objc public protocol EventBusEventListener: AnyObject {
    func eventBus(event: EventBusEvent)
}

/**
 Event bus for the SDK to be notified of events of the SDK.

 At this time, there is no added `userInfo` that `NotificationCenter` gives you. This is because
 that's error prone to have a generically typed `[String: Any]` scattered across the SDK.
 Instead, it's preferred that the listener receives an alert for the event and then
 if they need some information, they can query for that information.

 Example: Receive an event that a customer is identified in the SDK.
 Listeners get the notification and then they will query the SDK that manages the customer profile
 to get the new profile information.
 */
public protocol EventBus: AutoMockable {
    func post(_ event: EventBusEvent)
    func register(_ listener: EventBusEventListener, event: EventBusEvent)
    func unregister(_ listener: EventBusEventListener)
}

@objc public enum EventBusEvent: Int {
    case identifiedCustomer

    var name: String {
        switch self {
        case .identifiedCustomer: return "identifiedCustomer"
        }
    }
}

/**
 Custom `NotificationCenter` to avoid using the default customer app default center.
 Also, makes using notification center mockable to test SDK behavior.
 */
// sourcery: InjectRegister = "EventBus"
public class CioNotificationCenter: NotificationCenter, EventBus {
    public func post(_ event: EventBusEvent) {
        post(name: NSNotification.Name(event.name), object: nil, userInfo: nil)
    }

    public func unregister(_ listener: EventBusEventListener) {
        removeObserver(listener)
    }

    public func register(_ listener: EventBusEventListener, event: EventBusEvent) {
        addObserver(listener, selector: #selector(listener.eventBus(event:)), name: NSNotification.Name(event.name),
                    object: nil)
    }
}
