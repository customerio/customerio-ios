import Foundation

/// Defines a structure for events in the system.
///
/// Each specific event type conforms to `EventRepresentable`, making them compatible with the EventBus system.
/// Events include a `params` dictionary for additional data, enhancing flexibility.
public protocol EventRepresentable {
    var params: [String: AnyHashable] { get }
}

struct ProfileIdentifiedEvent: EventRepresentable {
    var params: [String: AnyHashable] = [:]
    let identifier: String
}

struct ScreenViewedEvent: EventRepresentable {
    var params: [String: AnyHashable] = [:]
    let name: String
}

struct ResetEvent: EventRepresentable {
    var params: [String: AnyHashable] = [:]
}

struct TrackMetricEvent: EventRepresentable {
    var params: [String: AnyHashable] = [:]
    let deliveryID: String
    let event: String
    let deviceToken: String
}
