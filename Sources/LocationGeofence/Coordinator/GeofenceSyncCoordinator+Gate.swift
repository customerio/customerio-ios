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

    /// What a movement pass did, kept separate from whether it succeeded.
    ///
    /// Not the same thing: a failed remote refresh still re-arms the trigger from cache before
    /// returning its failure, and it is the re-centre — not the result — that an older replay
    /// must not undo.
    struct MovementPassOutcome {
        let result: Result<Void, GeofenceSyncError>
        let reCentred: Bool
    }

    /// What a movement got when it reached the gate.
    enum GateOutcome: Equatable {
        case taken
        /// Another pass holds the gate; this movement is queued if it is the newest waiting.
        case deferred
        /// A newer movement has already re-centred. Running would move the trigger backwards.
        case overtaken
    }

    func nextMovementSequence() -> UInt64 {
        movementSequence.mutating { value in
            value += 1
            return value
        }
    }

    /// Records that `sequence` has re-centred the trigger. Monotonic: passes complete out of
    /// order, and an older one finishing last must not un-apply a newer one.
    ///
    /// Only ever called with a sequence issued by `nextMovementSequence`. That is what keeps a
    /// fresh arrival ahead of everything applied, and so what keeps the staleness test in
    /// `acquireGateOrDefer` from refusing real movements.
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
        // Not checked for staleness here. Clearing the queue frees the gate before this task
        // starts, so anything decided at this point can be false by the time the replay acquires:
        // `acquireGateOrDefer` makes the comparison and the acquisition one step instead.
        Task { [weak self] in
            _ = await self?.handleMovement(
                latitude: pending.latitude, longitude: pending.longitude,
                anchorIsLiveFix: pending.anchorIsLiveFix, sequence: pending.sequence
            )
        }
    }

    /// - Parameter sequence: arrival order. A replay carries the sequence of the movement it is
    ///   replaying rather than taking a new one, so being re-deferred cannot make stale
    ///   coordinates look like the newest thing to arrive.
    func handleMovement(
        latitude: Double, longitude: Double, anchorIsLiveFix: Bool, sequence: UInt64
    ) async -> Result<Void, GeofenceSyncError> {
        // Recorded, not dropped — see `deferredMovement`. Taking the gate, judging staleness and
        // recording the loss are one step on purpose: see `acquireGateOrDefer`.
        switch acquireGateOrDefer(
            DeferredMovement(
                latitude: latitude, longitude: longitude, anchorIsLiveFix: anchorIsLiveFix,
                sequence: sequence
            )
        ) {
        case .overtaken:
            logger.geofenceSyncSkipped(reason: .movementOvertaken)
            return .failure(.alreadyInProgress)
        case .deferred:
            logger.geofenceSyncSkipped(reason: .refreshInProgress)
            return .failure(.alreadyInProgress)
        case .taken:
            break
        }
        let expectedUserId = identifiedUserId
        let outcome = await performMovement(
            expectedUserId: expectedUserId, latitude: latitude, longitude: longitude,
            anchorIsLiveFix: anchorIsLiveFix
        )
        // Keyed on the re-centre, not on success, and before the release so a replay draining off
        // it compares against this pass. A pass that moved nothing must not retire a deferral that
        // is still the best information available; a pass that moved the trigger must, even when
        // it reports failure.
        if outcome.reCentred { noteMovementApplied(sequence) }
        let cleaned = await cleanupIfUserChanged(expectedUserId: expectedUserId)
        releaseGate()
        if cleaned { retryForCurrentUser(latitude: latitude, longitude: longitude, anchorIsLiveFix: anchorIsLiveFix) }
        drainDeferredMovement(userChanged: cleaned)
        return outcome.result
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
    func acquireGateOrDefer(_ movement: DeferredMovement) -> GateOutcome {
        refreshInProgress.mutating { inProgress in
            // Judged in here, not by the caller. A newer movement can take the gate, re-centre and
            // publish its sequence between a check made outside and the acquisition below — so a
            // replay that read "not overtaken" would still run at coordinates already superseded.
            // A fresh arrival can never lose this test: its sequence postdates every applied one.
            if appliedMovementSequence.wrappedValue >= movement.sequence { return .overtaken }
            if inProgress {
                // Highest sequence wins rather than last writer. A replay carries its ORIGINAL
                // sequence and can lose the gate after a newer arrival has already queued;
                // overwriting would put the older coordinates back in front.
                if (deferredMovement.wrappedValue?.sequence ?? 0) < movement.sequence {
                    deferredMovement.wrappedValue = movement
                }
                return .deferred
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
            //
            // Only what this pass outranks, for the same reason the deferring branch keeps the
            // highest: a replay can acquire a briefly free gate while a NEWER arrival waits behind
            // it, and clearing unconditionally would drop that arrival entirely.
            if (deferredMovement.wrappedValue?.sequence ?? 0) <= movement.sequence {
                deferredMovement.wrappedValue = nil
            }
            return .taken
        }
    }

    /// Drops any queued movement and frees the gate in ONE critical section.
    ///
    /// Two steps let a movement publish between them: it finds the gate still held, queues itself,
    /// and the clear has already run — so a movement belonging to the profile a reset is clearing
    /// survives it, and a later drain re-centres the trigger to that old position. Inside the
    /// section a movement either lands before the clear and is discarded with the rest, or after
    /// the release and takes the gate on its own terms.
    func discardDeferredAndReleaseGate() {
        refreshInProgress.mutating { inProgress in
            deferredMovement.wrappedValue = nil
            inProgress = false
        }
    }

    /// Takes the gate and stamps the pass with its arrival order, in ONE critical section.
    ///
    /// Allocating after the acquisition inverts the ordering it exists to express: a movement
    /// arriving in the gap allocates FIRST and so carries a LOWER sequence than the pass that was
    /// already holding the gate, and is then retired as overtaken by coordinates that are in fact
    /// older. Whoever takes the gate first must hold the earlier sequence.
    ///
    /// - Returns: the sequence to record on completion, or nil when another call holds the gate.
    func acquireGateWithSequence() -> UInt64? {
        refreshInProgress.mutating { inProgress in
            if inProgress { return nil }
            inProgress = true
            return nextMovementSequence()
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
