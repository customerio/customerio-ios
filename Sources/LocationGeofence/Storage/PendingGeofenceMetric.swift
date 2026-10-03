import CioInternalCommon
import Foundation

struct PendingGeofenceMetric: Codable, Equatable, Sendable, GeofenceMetric {
    let geofenceId: String
    let transition: GeofenceTransition
    let timestamp: Date
    let userId: String
    /// Resolved at capture so a delayed flush has it after the geofence leaves the cache.
    let name: String?
    let transitionId: String
    /// Optional so rows persisted before geosets still decode.
    let geosetId: String?
    /// Optional so rows persisted before metadata still decode.
    let metadata: [String: GeofenceMetadataValue]?
    let visitId: String?
    let enteredAt: Date?
    let dwellThresholdSeconds: Int?
    let dwellDurationSeconds: Int?
    let detectionSource: String?

    /// Includes `userId`: the queue survives sign-out, so one crossing can be queued under two users.
    /// Includes `transitionId`, the occurrence: two visits' facts in one second stay two rows, while
    /// a retried fact repeats its occurrence and lands on the row already queued. Derived, never
    /// stored, so rows persisted under an older key still match their own removal. Escaped so a
    /// `_` in a value can't imitate a boundary.
    var key: String {
        let sec = Int(timestamp.timeIntervalSince1970)
        var components = [geofenceId, transition.rawValue, "\(sec)", userId, transitionId]
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
        metadata: [String: GeofenceMetadataValue]? = nil,
        visitId: String? = nil,
        enteredAt: Date? = nil,
        dwellThresholdSeconds: Int? = nil,
        dwellDurationSeconds: Int? = nil,
        detectionSource: String? = nil
    ) {
        self.geofenceId = geofenceId
        self.transition = transition
        self.timestamp = timestamp
        self.userId = userId
        self.name = name
        self.transitionId = transitionId
        self.geosetId = geosetId
        self.metadata = metadata
        self.visitId = visitId
        self.enteredAt = enteredAt
        self.dwellThresholdSeconds = dwellThresholdSeconds
        self.dwellDurationSeconds = dwellDurationSeconds
        self.detectionSource = detectionSource
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
        case visitId = "visit_id"
        case enteredAt = "entered_at"
        case dwellThresholdSeconds = "dwell_threshold_seconds"
        case dwellDurationSeconds = "dwell_duration_seconds"
        case detectionSource = "detection_source"
    }

    func withResolved(name: String?, metadata: [String: GeofenceMetadataValue]?) -> PendingGeofenceMetric {
        PendingGeofenceMetric(
            geofenceId: geofenceId,
            transition: transition,
            timestamp: timestamp,
            userId: userId,
            name: name,
            transitionId: transitionId,
            geosetId: geosetId,
            metadata: metadata,
            visitId: visitId,
            enteredAt: enteredAt,
            dwellThresholdSeconds: dwellThresholdSeconds,
            dwellDurationSeconds: dwellDurationSeconds,
            detectionSource: detectionSource
        )
    }
}
