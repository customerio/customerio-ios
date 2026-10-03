import CioInternalCommon
import Foundation

/// One crossing handed to `GeofenceEventTracker`: what happened, the visit it closes or qualifies,
/// and who it may be delivered for. At most one of `dwell` and `exit` is set.
struct GeofenceCrossing: Sendable {
    let geofenceId: String
    let transition: GeofenceTransition
    let occurredAt: Date
    let dwell: GeofenceDwellContext?
    let exit: GeofenceExitContext?
    /// Drop the crossing unless this is still the identified user. Nil accepts whoever is current.
    let expectedUserId: String?
}

extension GeofenceCrossing {
    /// Fans the crossing out to one row per geoset the geofence belongs to, all stamped `userId`.
    func pendingMetrics(userId: String, cachedGeofence: Geofence?) -> [PendingGeofenceMetric] {
        var seenGeosetIds = Set<String>()
        let memberGeosetIds = (cachedGeofence?.geosetIds ?? []).filter { !$0.isEmpty && seenGeosetIds.insert($0).inserted }
        let geosetIds: [String?] = memberGeosetIds.isEmpty ? [nil] : memberGeosetIds
        // One transitionId for the whole crossing, so downstream correlates the fan-out. A dwell
        // reuses its visit's ID, so a crash between outbox persistence and the emitted-state write
        // stays idempotent downstream.
        let transitionId = dwell?.visitId ?? UUID().uuidString
        return geosetIds.map { geosetId in
            PendingGeofenceMetric(
                geofenceId: geofenceId,
                transition: transition,
                timestamp: occurredAt,
                userId: userId,
                name: cachedGeofence?.name,
                transitionId: transitionId,
                geosetId: geosetId,
                // Fallback for an evicted geofence; delivery prefers the live cache.
                metadata: cachedGeofence?.metadata,
                visitId: dwell?.visitId ?? exit?.visitId,
                enteredAt: dwell?.enteredAt ?? exit?.enteredAt,
                dwellThresholdSeconds: dwell?.thresholdSeconds,
                dwellDurationSeconds: dwell?.durationSeconds,
                visitDurationSeconds: exit?.durationSeconds,
                detectionSource: dwell?.detectionSource ?? exit?.detectionSource
            )
        }
    }
}
