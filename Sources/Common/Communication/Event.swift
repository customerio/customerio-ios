import Foundation

/// Defines a structure for events in the system.
///
/// Each specific event type conforms to `EventRepresentable`, making them compatible with the EventBus system.
/// Events include a `params` dictionary for additional data, enhancing flexibility.
public protocol EventRepresentable: Codable, Equatable {
    var params: [String: String] { get }
}

public struct ProfileIdentifiedEvent: EventRepresentable {
    public var params: [String: String] = [:]
    public let identifier: String

    public init(identifier: String, params: [String: String] = [:]) {
        self.identifier = identifier
        self.params = params
    }
}

public struct ScreenViewedEvent: EventRepresentable {
    public var params: [String: String] = [:]
    public let name: String

    public init(name: String, params: [String: String] = [:]) {
        self.name = name
        self.params = params
    }
}

public struct ResetEvent: EventRepresentable {
    public var params: [String: String] = [:]

    public init(params: [String: String] = [:]) {
        self.params = params
    }
}

struct TrackMetricEvent: EventRepresentable {
    var params: [String: String] = [:]
    let deliveryID: String
    let event: String
    let deviceToken: String

    init(deliveryID: String, event: String, deviceToken: String, params: [String: String] = [:]) {
        self.params = params
        self.deliveryID = deliveryID
        self.event = event
        self.deviceToken = deviceToken
    }
}

struct NewSubscriptionEvent: EventRepresentable {
    var params: [String: String] = [:]
    let subscribedEventType: String

    init<E: EventRepresentable>(subscribedEventType: E.Type, params: [String: String] = [:]) {
        self.subscribedEventType = String(describing: subscribedEventType)
    }
}
