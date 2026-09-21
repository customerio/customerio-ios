import CioInternalCommon
import Foundation

/// The refresh gate and the work that waits on it, split from the coordinator's core so both stay
/// under the file cap. `internal` rather than `private` only because of that split.
extension GeofenceSyncCoordinatorImpl {
    /// Coordinates for a movement pass awaiting its turn at the gate.
    struct DeferredMovement {
        let latitude: Double
        let longitude: Double
        let anchorIsLiveFix: Bool
        /// Arrival order, carried so a replay can be discarded once a newer movement has run.
        let sequence: UInt64
    }

    func nextMovementSequence() -> UInt64 {
        movementSequence.mutating { value in
            value += 1
            return value
        }
    }

    /// Records that `sequence` has re-centred the trigger. Monotonic: passes complete out of
    /// order, and an older one finishing last must not un-apply a newer one.
    func noteMovementApplied(_ sequence: UInt64) {
        appliedMovementSequence.mutating { value in
            value = max(value, sequence)
        }
    }

    /// After a cleanup for an identity change, the device monitors nothing — and the new user's own
    /// refresh may already have been dropped on the gate this operation held. Re-run for whoever is
    /// signed in now, with this operation's seconds-old coordinates, so a user switch converges to a
    /// registered state instead of an outage lasting until the next launch. Loop-safe: a retry only
    /// re-fires if the identity changes yet again during the retry itself.
    func retryForCurrentUser(latitude: Double, longitude: Double, anchorIsLiveFix: Bool) {
        guard identifiedUserId != nil else { return }
        Task { [weak self] in
            _ = await self?.refresh(
                latitude: latitude, longitude: longitude, anchorIsLiveFix: anchorIsLiveFix
            )
        }
    }

    /// Replays a movement pass that lost the gate, once the holder has released it.
    ///
    /// Taken and cleared in one step so a movement deferred DURING the replay is left for that
    /// replay's own release rather than being lost or replayed twice. Fired on a Task for the same
    /// reason `retryForCurrentUser` is: the gate is free but this call site is still unwinding the
    /// pass that freed it.
    ///
    /// Dropped outright when the user changed under us — the coordinates belong to a profile this
    /// coordinator no longer serves, and `retryForCurrentUser` has already queued the right work.
    func drainDeferredMovement(userChanged: Bool) {
        let pending = deferredMovement.mutating { value -> DeferredMovement? in
            defer { value = nil }
            return value
        }
        guard let pending, !userChanged, identifiedUserId != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            // Re-checked HERE, not at drain time. Clearing the queue frees the gate before this
            // task starts, so a newer movement can take it and re-centre first; replaying then
            // would move the trigger BACK to the older coordinates.
            //
            // A replay that loses the gate instead of being discarded is re-deferred with its
            // original sequence, so the same comparison retires it at the next drain.
            guard appliedMovementSequence.wrappedValue < pending.sequence else {
                logger.geofenceSyncSkipped(reason: .movementOvertaken)
                return
            }
            _ = await handleMovement(
                latitude: pending.latitude, longitude: pending.longitude,
                anchorIsLiveFix: pending.anchorIsLiveFix, sequence: pending.sequence
            )
        }
    }

    /// Takes the gate, or records the movement for replay — in ONE critical section.
    ///
    /// Doing it in two steps loses the movement. Between `acquireGate()` answering false and the
    /// record landing, the holder can both release AND drain; the record then arrives with the gate
    /// already free and nothing left that will drain it, and the trigger stays on the circle the
    /// device just exited — the exact loss `deferredMovement` exists to prevent, reached through
    /// its own window.
    ///
    /// Serialising both against `refreshInProgress` closes it: either the record lands while the
    /// holder still holds the gate, so that holder's release drains it, or the release got there
    /// first and this call acquires the gate instead of deferring.
    ///
    /// Lock order is one-way. This takes `refreshInProgress` then `deferredMovement`; nothing takes
    /// them the other way round — `drainDeferredMovement` reads `deferredMovement` alone and fires
    /// its replay outside the critical section.
    func acquireGateOrDefer(_ movement: DeferredMovement) -> Bool {
        refreshInProgress.mutating { inProgress in
            if inProgress {
                deferredMovement.wrappedValue = movement
                return false
            }
            inProgress = true
            // A movement that actually runs supersedes any older one still queued: both describe
            // the same journey and this one's coordinates are newer. Without it, a deferral
            // recorded before this pass replays after it and moves the trigger BACK.
            //
            // Cleared in here, not after the guard. Outside the section it is the same two-step
            // shape this method exists to close: a movement that lost the gate and recorded itself
            // correctly would then be wiped by the winner, and in that ordering the record it
            // wipes is the NEWER one — the premise above inverted.
            deferredMovement.wrappedValue = nil
            return true
        }
    }

    /// Returns false when another call already holds the gate; the caller short-circuits.
    func acquireGate() -> Bool {
        refreshInProgress.mutating { inProgress in
            if inProgress { return false }
            inProgress = true
            return true
        }
    }

    func releaseGate() {
        refreshInProgress.wrappedValue = false
    }
}
