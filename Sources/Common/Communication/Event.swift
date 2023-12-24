import Foundation

/// Defines a structure for events in the system.
///
/// Each specific event type conforms to `EventRepresentable`, making them compatible with the EventBus system.
/// Events include a `params` dictionary for additional data, enhancing flexibility.
public protocol EventRepresentable: Equatable, Codable {
    /// A unique key representing the type of the event.
    var key: String { get }
    /// A unique identifier for each event instance, used for storage and retrieval.
    var storageId: String { get }
    /// Parameters associated with the event, represented as a dictionary.
    var params: [String: String] { get }
}

// Default key
public extension EventRepresentable {
    static var key: String {
        String(describing: Self.self)
    var key: String {
        Self.key
    }
}

// MARK: - Event Types Registry

/// Registry of all event types in the system.
public enum EventTypesRegistry {
    static func allEventTypes() -> [any EventRepresentable.Type] {
        // Add all your event types here
        [
            ProfileIdentifiedEvent.self,
            ScreenViewedEvent.self,
            ResetEvent.self,
            TrackMetricEvent.self,
            TrackInAppMetricEvent.self,
            RegisterDeviceTokenEvent.self,
            DeleteDeviceTokenEvent.self,
            NewSubscriptionEvent.self
        ]
    }
}

// MARK: - Event Structs

public struct ProfileIdentifiedEvent: EventRepresentable {
    public let storageId: String
    public let params: [String: String]
    public let identifier: String

    public init(storageId: String = UUID().uuidString, identifier: String, params: [String: String] = [:]) {
        self.storageId = storageId
        self.identifier = identifier
        self.params = params
    }
}

public struct ScreenViewedEvent: EventRepresentable {
    public let storageId: String
    public let params: [String: String]
    public let name: String

    public init(storageId: String = UUID().uuidString, name: String, params: [String: String] = [:]) {
        self.storageId = storageId
        self.name = name
        self.params = params
    }
}

public struct ResetEvent: EventRepresentable {
    public let storageId: String
    public let params: [String: String]

    public init(storageId: String = UUID().uuidString, params: [String: String] = [:]) {
        self.storageId = storageId
        self.params = params
    }
}

public struct TrackMetricEvent: EventRepresentable {
    public let storageId: String
    public let params: [String: String]
    public let deliveryID: String
    public let event: String
    public let deviceToken: String

    public init(storageId: String = UUID().uuidString, deliveryID: String, event: String, deviceToken: String, params: [String: String] = [:]) {
        self.storageId = storageId
        self.params = params
        self.deliveryID = deliveryID
        self.event = event
        self.deviceToken = deviceToken
    }
}

public struct TrackInAppMetricEvent: EventRepresentable {
    public let storageId: String
    public let params: [String: String]
    public let deliveryID: String
    public let event: String

    public init(storageId: String = UUID().uuidString, deliveryID: String, event: String, params: [String: String] = [:]) {
        self.storageId = storageId
        self.params = params
        self.deliveryID = deliveryID
        self.event = event
    }
}

public struct RegisterDeviceTokenEvent: EventRepresentable {
    public let storageId: String
    public let params: [String: String]
    public let token: String

    public init(storageId: String = UUID().uuidString, token: String, params: [String: String] = [:]) {
        self.storageId = storageId
        self.token = token
        self.params = params
    }
}

public struct DeleteDeviceTokenEvent: EventRepresentable {
    public let storageId: String
    public let params: [String: String]

    public init(storageId: String = UUID().uuidString, params: [String: String] = [:]) {
        self.storageId = storageId
        self.params = params
    }
}

public struct NewSubscriptionEvent: EventRepresentable {
    public let storageId: String
    public let params: [String: String]
    public let subscribedEventType: String

    init<E: EventRepresentable>(storageId: String = UUID().uuidString, subscribedEventType: E.Type, params: [String: String] = [:]) {
        self.storageId = storageId
        self.subscribedEventType = E.key
        self.params = params
    }
}
