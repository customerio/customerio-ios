import Foundation

/// A geofence transition carrying the fields needed to build its `/track` analytics payload.
///
/// Both delivery paths conform — `PendingGeofenceMetric` (direct-HTTP) and
/// `TrackGeofenceMetricEvent` (EventBus → DataPipeline) — so the property shape is defined once.
public protocol GeofenceMetric {
    var geofenceId: String { get }
    var transition: GeofenceTransition { get }
    var timestamp: Date { get }
    /// The geofence's name, or `nil` when unavailable.
    var name: String? { get }
}

public extension GeofenceMetric {
    /// `/track` event properties. `geofence_name` is included only when a name is available.
    var trackEventProperties: [String: Any] {
        var properties: [String: Any] = [
            "geofence_id": geofenceId,
            "transition_type": transition.rawValue,
            "timestamp": Int(timestamp.timeIntervalSince1970)
        ]
        if let name {
            properties["geofence_name"] = name
        }
        return properties
    }
}
