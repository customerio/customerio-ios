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

/// Delivers a transition through the tracked path (cooldown, per-geoset fan-out, persistence).
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
