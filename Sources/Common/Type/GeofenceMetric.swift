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
    /// Uniquely identifies this transition; stable across delivery retries.
    var transitionId: String { get }
    /// The geoset this event was emitted for, or `nil` when the geofence is in
    /// no geoset. A geofence in N geosets produces N metrics per transition,
    /// each carrying one geoset ID, so every event stands alone.
    var geosetId: String? { get }
}

public extension GeofenceMetric {
    /// `/track` event name. The same name for every transition; the direction is the
    /// `transition` property.
    var trackEventName: String { "Geofence Transition" }

    /// `/track` event properties. `geofenceName` and `geosetId` are included only when available.
    /// `transitionId` uniquely identifies the transition and stays stable across delivery retries.
    /// `timestamp` is not a property — it is set on the event envelope by each path.
    var trackEventProperties: [String: Any] {
        var properties: [String: Any] = [
            "transition": transition.rawValue,
            "geofenceId": geofenceId,
            "transitionId": transitionId
        ]
        if let name {
            properties["geofenceName"] = name
        }
        if let geosetId {
            // Numeric ids go out as a number (type-preserving) so scalar campaign matching is consistent.
            properties["geosetId"] = Int64(geosetId) ?? geosetId
        }
        return properties
    }
}
