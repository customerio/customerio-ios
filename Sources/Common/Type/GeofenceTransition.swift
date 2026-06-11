import Foundation

/// Transition type for geofence boundary crossings.
///
/// Lives in Common (not Location) so cross-module consumers — `TrackGeofenceMetricEvent`
/// in the EventBus path, `PendingGeofenceMetric` in the queue path — can carry the type
/// directly instead of round-tripping through a `String`. Raw values are the wire format
/// (`"enter"` / `"exit"`) and match the Android SDK.
public enum GeofenceTransition: String, Codable, Sendable {
    case enter
    case exit
}

public extension GeofenceTransition {
    /// Analytics event name for this transition. Matches the Android SDK's
    /// `"Geofence Entered"` / `"Geofence Exited"`.
    var trackEventName: String {
        switch self {
        case .enter: return "CIO Geofence Entered"
        case .exit: return "CIO Geofence Exited"
        }
    }
}
