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

/// The visit an EXIT ends. `visitId` travels on every EXIT attributed to a visit; `enteredAt` and
/// `durationSeconds` together, when the entry was observed and the span is on one monotonic
/// timeline, else both nil. `visitDurationUncertaintySeconds` goes with the duration: the whole
/// seconds between the last moment the device was proven inside and the moment the departure was
/// observed, at most the duration — the gap since the latest inside evidence (or the entry) for a
/// circle EXIT the OS decided and dated, as for a polygon left by a fix or its covering circle,
/// since the OS samples location sparsely; the whole stay for one the monitor could only date at
/// receipt.
struct GeofenceExitContext: Sendable, Equatable {
    let visitId: String
    let enteredAt: Date?
    let durationSeconds: Int?
    let visitDurationUncertaintySeconds: Int?
    let detectionSource: String
}

/// What became of a dwell handed to the outbox.
enum GeofenceDwellDelivery: Equatable, Sendable {
    /// Its rows are in the outbox.
    case persisted
    /// The outbox could not be written, or read to append to: asking again may succeed.
    case writeFailed
    /// Refused for good: no user is identified, or not the one the dwell was for.
    case refused
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
    /// `trackDwell`, telling a refusal for good from a write that may succeed if asked again.
    func deliverDwell(
        geofenceId: String, occurredAt: Date, context: GeofenceDwellContext, expectedUserId: String?
    ) async -> GeofenceDwellDelivery
    /// Delivers an exit with its optional visit context. Dropped when `expectedUserId` is set and
    /// is no longer the identified user.
    func trackExit(
        geofenceId: String, occurredAt: Date, context: GeofenceExitContext?, expectedUserId: String?
    ) async
}

extension GeofenceTransitionEmitting {
    /// For an emitter that cannot tell the two apart: a dwell not persisted may be asked again.
    func deliverDwell(
        geofenceId: String, occurredAt: Date, context: GeofenceDwellContext, expectedUserId: String?
    ) async -> GeofenceDwellDelivery {
        await trackDwell(geofenceId: geofenceId, occurredAt: occurredAt, context: context, expectedUserId: expectedUserId)
            ? .persisted : .writeFailed
    }
}

extension GeofenceDwellReservation {
    /// The context a dwell is delivered with for `visitId`, exactly as reserved.
    func context(visitId: String) -> GeofenceDwellContext {
        GeofenceDwellContext(
            visitId: visitId, enteredAt: enteredAt, thresholdSeconds: thresholdSeconds,
            durationSeconds: durationSeconds, detectionSource: detectionSource
        )
    }
}
