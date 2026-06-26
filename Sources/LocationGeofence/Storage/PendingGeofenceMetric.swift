import CioInternalCommon
import Foundation

/// A geofence transition queued for delivery (direct-HTTP when stamped with a
/// userId, EventBus → DataPipeline anonymous when not).
struct PendingGeofenceMetric: Codable, Equatable, Sendable, GeofenceMetric {
    let geofenceId: String
    let transition: GeofenceTransition
    let timestamp: Date
    /// The userId identified at capture time, or `nil` if none was identified.
    let userId: String?
    /// The geofence's name, resolved at capture time, or `nil` when unavailable. Travels with the
    /// metric so a delayed flush still has it even after the geofence leaves the cache.
    let name: String?
    let transitionId: String

    // === TESTING-ONLY (geofence-testing branch) — must not merge. ===
    /// Device location the transition fired at, distance from it to the geofence center, and the
    /// geofence radius — surfaced in the payload so distance vs radius can be verified.
    let triggeredLatitude: Double?
    let triggeredLongitude: Double?
    let distanceFromGeofenceMeters: Double?
    let geofenceRadius: Double?
    // === END TESTING-ONLY ===

    /// Composite key over `(geofenceId, transition, timestamp_sec)` used for
    /// storage-layer dedup. Matches Android's `PendingGeofenceDelivery.key`.
    /// Seconds (not ms) — cooldown gate dedups by `(geofenceId, transition)`
    /// upstream, so finer precision adds nothing.
    var key: String {
        let sec = Int(timestamp.timeIntervalSince1970)
        return "\(geofenceId)_\(transition.rawValue)_\(sec)"
    }

    init(
        geofenceId: String,
        transition: GeofenceTransition,
        timestamp: Date,
        userId: String?,
        name: String?,
        transitionId: String,
        // TESTING-ONLY (geofence-testing branch): default nil so non-testing callers/tests are unaffected.
        triggeredLatitude: Double? = nil,
        triggeredLongitude: Double? = nil,
        distanceFromGeofenceMeters: Double? = nil,
        geofenceRadius: Double? = nil
    ) {
        self.geofenceId = geofenceId
        self.transition = transition
        self.timestamp = timestamp
        self.userId = userId
        self.name = name
        self.transitionId = transitionId
        self.triggeredLatitude = triggeredLatitude
        self.triggeredLongitude = triggeredLongitude
        self.distanceFromGeofenceMeters = distanceFromGeofenceMeters
        self.geofenceRadius = geofenceRadius
    }

    enum CodingKeys: String, CodingKey {
        case geofenceId = "geofence_id"
        case transition
        case timestamp
        case userId = "user_id"
        case name = "geofence_name"
        case transitionId = "transition_id"
        // TESTING-ONLY (geofence-testing branch)
        case triggeredLatitude = "triggered_latitude"
        case triggeredLongitude = "triggered_longitude"
        case distanceFromGeofenceMeters = "distance_from_geofence_meters"
        case geofenceRadius = "geofence_radius"
    }
}

// === TESTING-ONLY (geofence-testing branch) — must not merge. ===
extension PendingGeofenceMetric {
    /// Base track properties plus testing diagnostics (trigger location, distance-to-center, radius,
    /// and the capture timestamp) so geofence accuracy can be verified directly from the CDP payload.
    var trackEventPropertiesForTesting: [String: Any] {
        var properties = trackEventProperties
        properties["timestamp"] = timestamp.string(format: .iso8601WithMilliseconds)
        if let triggeredLatitude { properties["triggeredLatitude"] = triggeredLatitude }
        if let triggeredLongitude { properties["triggeredLongitude"] = triggeredLongitude }
        if let distanceFromGeofenceMeters { properties["distanceFromGeofenceMeters"] = distanceFromGeofenceMeters }
        if let geofenceRadius { properties["geofenceRadius"] = geofenceRadius }
        return properties
    }
}

// === END TESTING-ONLY ===
