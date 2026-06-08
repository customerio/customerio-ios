import CioInternalCommon
import Foundation

/// A geofence transition queued for delivery (direct-HTTP when stamped with a
/// userId, EventBus → DataPipeline anonymous when not).
struct PendingGeofenceMetric: Codable, Equatable, Sendable {
    let geofenceId: String
    let transition: GeofenceTransition
    let latitude: Double?
    let longitude: Double?
    let timestamp: Date
    /// The userId identified at capture time, or `nil` if none was identified.
    let userId: String?

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
        timestamp: Date,
        userId: String? = nil
    ) {
        self.geofenceId = geofenceId
        self.transition = transition
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.userId = userId
    }

    enum CodingKeys: String, CodingKey {
        case geofenceId = "geofence_id"
        case transition
        case latitude
        case longitude
        case timestamp
        case userId = "user_id"
    }
}
