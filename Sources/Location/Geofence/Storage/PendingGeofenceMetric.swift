import CioInternalCommon
import Foundation

/// A geofence transition queued for direct-HTTP delivery.
struct PendingGeofenceMetric: Codable, Equatable, Sendable {
    let geofenceId: String
    let transition: GeofenceTransition
    let latitude: Double?
    let longitude: Double?
    let timestamp: Date

    /// Composite key over `(geofenceId, transition, timestamp_ms)` used for
    /// storage-layer dedup. Matches Android's `PendingGeofenceDelivery.key`.
    var key: String {
        let ms = Int(timestamp.timeIntervalSince1970 * 1000)
        return "\(geofenceId)_\(transition.rawValue)_\(ms)"
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
