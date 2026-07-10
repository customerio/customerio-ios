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
    /// The geoset this row was fanned out for, or `nil` when the geofence is in no geoset.
    /// One physical transition of a geofence in N geosets produces N rows, one per geoset.
    /// Optional so rows persisted by pre-geoset SDK versions still decode.
    let geosetId: String?
    /// Snapshot of the geofence's metadata at transition, the fallback when `deliver` can't find
    /// the geofence in cache. Optional so rows persisted before metadata still decode.
    let metadata: [String: GeofenceMetadataValue]?

    /// Composite key over `(geofenceId, transition, timestamp_sec, geosetId)` used for
    /// storage-layer dedup. Matches Android's `PendingGeofenceDelivery.key`.
    /// Seconds (not ms) — cooldown gate dedups by `(geofenceId, transition)`
    /// upstream, so finer precision adds nothing. The geoset suffix keeps the
    /// fan-out rows of one transition from colliding with each other.
    var key: String {
        let sec = Int(timestamp.timeIntervalSince1970)
        let base = "\(geofenceId)_\(transition.rawValue)_\(sec)"
        guard let geosetId else { return base }
        return "\(base)_\(geosetId)"
    }

    init(
        geofenceId: String,
        transition: GeofenceTransition,
        timestamp: Date,
        userId: String?,
        name: String?,
        transitionId: String,
        geosetId: String? = nil,
        metadata: [String: GeofenceMetadataValue]? = nil
    ) {
        self.geofenceId = geofenceId
        self.transition = transition
        self.timestamp = timestamp
        self.userId = userId
        self.name = name
        self.transitionId = transitionId
        self.geosetId = geosetId
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case geofenceId = "geofence_id"
        case transition
        case timestamp
        case userId = "user_id"
        case name = "geofence_name"
        case transitionId = "transition_id"
        case geosetId = "geoset_id"
        case metadata
    }

    /// Returns a copy with `name`/`metadata` replaced (used to prefer live cached values at send).
    /// All other fields, including the dedup `key` inputs, are unchanged.
    func withResolved(name: String?, metadata: [String: GeofenceMetadataValue]?) -> PendingGeofenceMetric {
        PendingGeofenceMetric(
            geofenceId: geofenceId,
            transition: transition,
            timestamp: timestamp,
            userId: userId,
            name: name,
            transitionId: transitionId,
            geosetId: geosetId,
            metadata: metadata
        )
    }
}
