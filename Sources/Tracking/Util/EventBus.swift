import Foundation

public typealias EventBusEventListener = (EventBusEvent) -> Void
public typealias EventBusListenerReference = NSObjectProtocol

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
    func register(event: EventBusEvent, listener: @escaping EventBusEventListener) -> EventBusListenerReference
    func unregister(_ listener: EventBusListenerReference?)
}

public enum EventBusEvent: Int, CaseIterable {
    case identifiedCustomer

    static func from(name: String) -> EventBusEvent? {
        var returnEvent: EventBusEvent?

        allCases.forEach { event in
            if event.name == name {
                returnEvent = event
            }
        }

        return returnEvent
    }

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

    public func unregister(_ listener: EventBusListenerReference?) {
        if let listener = listener {
            removeObserver(listener)
        }
    }

    /// `addObserver` copies the lambda and returns a reference for you. Because it uses a reference we can
    /// override the lambda in this class without messing up the `unregister` to reference the passed in lambda.
    public func register(event: EventBusEvent, listener: @escaping EventBusEventListener) -> EventBusListenerReference {
        addObserver(forName: NSNotification.Name(event.name), object: nil, queue: nil) { notification in
            guard let event = EventBusEvent.from(name: notification.name.rawValue) else {
                return
            }

            listener(event)
        }
    }
}
