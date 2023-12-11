import Foundation

/// Defines a structure for events in the system.
///
/// Each specific event type conforms to `EventRepresentable`, making them compatible with the EventBus system.
/// Events include a `params` dictionary for additional data, enhancing flexibility.
public protocol EventRepresentable: Codable, Equatable {
    var params: [String: String] { get }
}

struct ProfileIdentifiedEvent: EventRepresentable, Codable {
    var params: [String: String] = [:]
    let identifier: String
}

struct ScreenViewedEvent: EventRepresentable, Codable {
    var params: [String: String] = [:]
    let name: String
}

struct ResetEvent: EventRepresentable, Codable {
    var params: [String: String] = [:]
}

struct TrackMetricEvent: EventRepresentable, Codable {
    var params: [String: String] = [:]
    let deliveryID: String
    let event: String
    let deviceToken: String
}

struct NewSubscriptionEvent: EventRepresentable, Codable {
    var params: [String: String] = [:]
    let subscribedEventType: String

    init<E: EventRepresentable>(subscribedEventType: E.Type) {
        self.subscribedEventType = String(describing: subscribedEventType)
    }
}
