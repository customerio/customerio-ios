import Foundation

public typealias AnyEventRepresentable = any EventRepresentable

/// Protocol defining the structure and requirements of events in the system.
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
    /// Timestamp indicating when the event was created.
    var timestamp: Date { get }
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

    static func getEventType(for key: String) throws -> (any EventRepresentable.Type) {
        switch key {
        case ProfileIdentifiedEvent.key:
            return ProfileIdentifiedEvent.self
        case ScreenViewedEvent.key:
            return ScreenViewedEvent.self
        case ResetEvent.key:
            return ResetEvent.self
        case TrackMetricEvent.key:
            return TrackMetricEvent.self
        case TrackInAppMetricEvent.key:
            return TrackInAppMetricEvent.self
        case RegisterDeviceTokenEvent.key:
            return RegisterDeviceTokenEvent.self
        case DeleteDeviceTokenEvent.key:
            return DeleteDeviceTokenEvent.self
        case NewSubscriptionEvent.key:
            return NewSubscriptionEvent.self
        default:
            throw EventBusError.invalidEventType
        }
    }
}

// MARK: - Event Structs

// Each event struct should have properties relevant to its specific use case.
// They must include `storageId`, `params`, and any other relevant information.

public struct ProfileIdentifiedEvent: EventRepresentable {
    public let storageId: String
    public let params: [String: String]
    public let identifier: String
    public let timestamp: Date

    public init(storageId: String = UUID().uuidString, identifier: String, timestamp: Date = Date(), params: [String: String] = [:]) {
        self.storageId = storageId
        self.identifier = identifier
        self.timestamp = timestamp
        self.params = params
    }
}

public struct ScreenViewedEvent: EventRepresentable {
    public let storageId: String
    public let params: [String: String]
    public let name: String
    public let timestamp: Date

    public init(storageId: String = UUID().uuidString, name: String, timestamp: Date = Date(), params: [String: String] = [:]) {
        self.storageId = storageId
        self.name = name
        self.timestamp = timestamp
        self.params = params
    }
}

public struct ResetEvent: EventRepresentable {
    public let storageId: String
    public let params: [String: String]
    public let timestamp: Date

    public init(storageId: String = UUID().uuidString, timestamp: Date = Date(), params: [String: String] = [:]) {
        self.storageId = storageId
        self.timestamp = timestamp
        self.params = params
    }
}

public struct TrackMetricEvent: EventRepresentable {
    public let storageId: String
    public let params: [String: String]
    public let deliveryID: String
    public let event: String
    public let deviceToken: String
    public let timestamp: Date

    public init(storageId: String = UUID().uuidString, deliveryID: String, event: String, deviceToken: String, timestamp: Date = Date(), params: [String: String] = [:]) {
        self.storageId = storageId
        self.params = params
        self.deliveryID = deliveryID
        self.event = event
        self.deviceToken = deviceToken
        self.timestamp = timestamp
    }
}

public struct TrackInAppMetricEvent: EventRepresentable {
    public let storageId: String
    public let params: [String: String]
    public let deliveryID: String
    public let event: String
    public let timestamp: Date

    public init(storageId: String = UUID().uuidString, deliveryID: String, event: String, timestamp: Date = Date(), params: [String: String] = [:]) {
        self.storageId = storageId
        self.params = params
        self.deliveryID = deliveryID
        self.event = event
        self.timestamp = timestamp
    }
}

public struct RegisterDeviceTokenEvent: EventRepresentable {
    public let storageId: String
    public let params: [String: String]
    public let token: String
    public let timestamp: Date

    public init(storageId: String = UUID().uuidString, token: String, timestamp: Date = Date(), params: [String: String] = [:]) {
        self.storageId = storageId
        self.token = token
        self.timestamp = timestamp
        self.params = params
    }
}

public struct DeleteDeviceTokenEvent: EventRepresentable {
    public let storageId: String
    public let params: [String: String]
    public let timestamp: Date

    public init(storageId: String = UUID().uuidString, timestamp: Date = Date(), params: [String: String] = [:]) {
        self.storageId = storageId
        self.timestamp = timestamp
        self.params = params
    }
}

public struct NewSubscriptionEvent: EventRepresentable {
    public let storageId: String
    public let params: [String: String]
    public let subscribedEventType: String
    public let timestamp: Date

    init<E: EventRepresentable>(storageId: String = UUID().uuidString, subscribedEventType: E.Type, timestamp: Date = Date(), params: [String: String] = [:]) {
        self.storageId = storageId
        self.subscribedEventType = E.key
        self.timestamp = timestamp
        self.params = params
    }
}
