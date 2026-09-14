import Foundation

/// Transition type for geofence boundary crossings.
///
/// Lives in Common (not Location) so cross-module consumers — `TrackGeofenceMetricEvent`
/// in the EventBus path, `PendingGeofenceMetric` in the queue path — can carry the type
/// directly instead of round-tripping through a `String`. Raw values are the wire format
/// (`"enter"` / `"exit"`) and match the Android SDK.
///
/// Spelled out rather than defaulted: the raw value is the `transition` property on the tracked
/// event, the Codable form of a persisted `PendingGeofenceMetric`, and part of both the pending
/// dedup key and the cooldown key. Defaulted, a rename of the case would change all four at once
/// — silently, since the api-docs baseline records no enum cases.
public enum GeofenceTransition: String, Codable, Sendable, CaseIterable {
    case enter
    case exit
}
