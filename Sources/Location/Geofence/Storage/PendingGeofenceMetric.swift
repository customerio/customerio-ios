import CioInternalCommon
import Foundation

/// A geofence transition queued for direct-HTTP delivery.
struct PendingGeofenceMetric: Codable, Equatable, Sendable {
    let id: UUID
    let geofenceId: String
    let transition: GeofenceTransition
    let latitude: Double?
    let longitude: Double?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        geofenceId: String,
        transition: GeofenceTransition,
        latitude: Double?,
        longitude: Double?,
        timestamp: Date
    ) {
        self.id = id
        self.geofenceId = geofenceId
        self.transition = transition
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case id
        case geofenceId = "geofence_id"
        case transition
        case latitude
        case longitude
        case timestamp
    }
}
