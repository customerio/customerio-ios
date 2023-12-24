import Foundation

public typealias AnyEventRepresentable = any EventRepresentable

/// Conformance to this protocol ensures compatibility with the EventBus system.
/// Events can carry additional data through a `params` dictionary, offering flexibility for different use cases.
public protocol EventRepresentable: Equatable, Codable {
    /// A unique key representing the event type.
    /// This is used to differentiate and manage different kinds of events.
    var key: String { get }
    /// A unique identifier for each event instance.
    /// This identifier aids in storage and retrieval operations.
    var storageId: String { get }
    /// A dictionary containing parameters or data associated with the event.
    var params: [String: String] { get }
}

// Default implementation for `EventRepresentable`
public extension EventRepresentable {
    // Provides a default implementation of the `key` property.
    /// It uses the type's name as a unique key.
    static var key: String {
        String(describing: Self.self)
    }

    /// Returns the default `key` for the instance.
    var key: String {
        Self.key
    }
}

// MARK: - Event Types Registry

/// A registry for all event types used within the system.
/// This enum can be extended to include new event types as they are defined.
public enum EventTypesRegistry {
    /// Returns an array of all event types available in the system.
    /// This is used to manage and interact with different types of events.
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

// Each event struct should have properties relevant to its specific use case.
// They must include `storageId`, `params`, and any other relevant information.

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
