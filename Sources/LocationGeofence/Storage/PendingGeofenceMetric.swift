import CioInternalCommon
import Foundation

/// A geofence transition queued for delivery. Always carries the userId identified at capture;
/// anonymous crossings are dropped before a row is created.
struct PendingGeofenceMetric: Codable, Equatable, Sendable, GeofenceMetric {
    let geofenceId: String
    let transition: GeofenceTransition
    let timestamp: Date
    let userId: String
    /// Resolved at capture so a delayed flush has it after the geofence leaves the cache.
    let name: String?
    let transitionId: String
    /// The geoset this row was fanned out for (one row per geoset), or `nil` for none. Optional so
    /// rows persisted by pre-geoset SDK versions still decode.
    let geosetId: String?
    /// Metadata at transition, the fallback when the geofence isn't cached at send. Optional so
    /// rows persisted before metadata still decode.
    let metadata: [String: GeofenceMetadataValue]?

    /// Dedup key over `(geofenceId, transition, timestamp_sec, userId, geosetId)`. Seconds suffice
    /// because the cooldown already dedups by `(geofenceId, transition)` upstream.
    ///
    /// `userId` is required: the queue survives sign-out while the cooldown doesn't, so one crossing
    /// can be queued under two users, and without it one row would be lost and the other
    /// misattributed. Android's `PendingGeofenceDelivery.key` omits the userId.
    ///
    /// Components are escaped so a value containing `_` can't imitate a boundary (user `a_42` vs
    /// user `a` in geoset `42`). Never persisted, so the escaping needs no migration.
    var key: String {
        let sec = Int(timestamp.timeIntervalSince1970)
        var components = [geofenceId, transition.rawValue, "\(sec)", userId]
        if let geosetId { components.append(geosetId) }
        return components.map(Self.escapedForKey).joined(separator: "_")
    }

    /// `%` first, so the next replacement doesn't re-escape it.
    private static func escapedForKey(_ component: String) -> String {
        component
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "_", with: "%5F")
    }

    init(
        geofenceId: String,
        transition: GeofenceTransition,
        timestamp: Date,
        userId: String,
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

    /// A copy with `name`/`metadata` replaced by live cached values at send; `key` is unchanged.
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
