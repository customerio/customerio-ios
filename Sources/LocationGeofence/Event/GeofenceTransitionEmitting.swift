import CioInternalCommon
import Foundation

struct GeofenceDwellContext: Sendable {
    let visitId: String
    /// Nil when the visit's entry was not observed: its start is only the first inside evidence.
    let enteredAt: Date?
    let thresholdSeconds: Int
    /// Nil on the same condition as `enteredAt`; it would be measured from that inferred start.
    let durationSeconds: Int?
    let detectionSource: String
}

/// Delivers a transition through the tracked path (cooldown dedup, per-geoset fan-out, persistence).
/// Lets a caller such as `GeofenceSyncCoordinator` fire a synthetic initial ENTER for a newly
/// registered geofence the device is already inside, without depending on the concrete tracker.
protocol GeofenceTransitionEmitting: Sendable {
    /// See `GeofenceEventTracker.trackTransition(geofenceId:transition:occurredAt:)`.
    func trackTransition(geofenceId: String, transition: GeofenceTransition, occurredAt: Date) async
    /// Delivers a dwell for one visit. Returns whether its rows were persisted. Dropped when
    /// `expectedUserId` is set and is no longer the identified user.
    func trackDwell(
        geofenceId: String, occurredAt: Date, context: GeofenceDwellContext, expectedUserId: String?
    ) async -> Bool
    /// Delivers an exit. Dropped when `expectedUserId` is set and is no longer the identified user.
    func trackExit(geofenceId: String, occurredAt: Date, expectedUserId: String?) async
}
