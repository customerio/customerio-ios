import CioInternalCommon
import Foundation

/// A geofence transition queued for direct-HTTP delivery.
struct PendingGeofenceMetric: Codable, Equatable, Sendable {
    let geofenceId: String
    let transition: GeofenceTransition
    let latitude: Double?
    let longitude: Double?
    let timestamp: Date

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
        latitude: Double?,
        longitude: Double?,
        timestamp: Date
    ) {
        self.geofenceId = geofenceId
        self.transition = transition
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case geofenceId = "geofence_id"
        case transition
        case latitude
        case longitude
        case timestamp
    }
}
