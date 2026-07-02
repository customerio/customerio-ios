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
        transitionId: String
    ) {
        self.geofenceId = geofenceId
        self.transition = transition
        self.timestamp = timestamp
        self.userId = userId
        self.name = name
        self.transitionId = transitionId
    }

    enum CodingKeys: String, CodingKey {
        case geofenceId = "geofence_id"
        case transition
        case timestamp
        case userId = "user_id"
        case name = "geofence_name"
        case transitionId = "transition_id"
    }
}
