import CioInternalCommon
import Foundation

/// The refresh gate and the work that waits on it. Split out to stay under the file cap, which is
/// the only reason members are internal.
extension GeofenceSyncCoordinatorImpl {
    /// Coordinates for a movement pass awaiting its turn at the gate.
    struct DeferredMovement {
        let latitude: Double
        let longitude: Double
        let anchorIsLiveFix: Bool
        /// Arrival order, carried so a replay can be discarded once a newer movement has run.
        let sequence: UInt64
        /// Carried so the replay judges membership from where the crossing happened. It ages while
        /// the holder runs; the resolver requests a new one past `movementFixMaxAge` (`heldFixUse`).
        let heldFix: ResolvedFix?
    }

    /// What a movement pass did, kept separate from whether it succeeded: a failed remote refresh
    /// still re-arms the trigger from cache, and it is the re-centre an older replay must not undo.
    struct MovementPassOutcome {
        let result: Result<Void, GeofenceSyncError>
        let reCentred: Bool
    }

    /// What a movement got when it reached the gate.
    enum GateOutcome: Equatable {
        /// Carries the sequence the pass runs under: a replay's own, or one minted here.
        case taken(sequence: UInt64)
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

    /// Records that `sequence` has re-centred the trigger. Monotonic: passes complete out of order.
    /// Only pass sequences from `nextMovementSequence`, or the staleness test in
    /// `acquireGateOrDefer` can refuse real movements.
    func noteMovementApplied(_ sequence: UInt64) {
        appliedMovementSequence.mutating { value in
            value = max(value, sequence)
        }
    }

    /// After a cleanup for an identity change the device monitors nothing, and the new user's own
    /// refresh may have been dropped on the gate this operation held. Re-runs for whoever is signed
    /// in now so a user switch doesn't leave monitoring off until the next launch. Loop-safe: a
    /// retry only re-fires if the identity changes again during it.
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
    /// Taken and cleared in one step so a movement deferred during the replay is left for that
    /// replay's own release, not lost or replayed twice. Dropped when the user changed: the
    /// coordinates belong to the old profile, and `retryForCurrentUser` has queued the right work.
    func drainDeferredMovement(userChanged: Bool) {
        let pending = deferredMovement.mutating { value -> DeferredMovement? in
            defer { value = nil }
            return value
        }
        guard let pending, !userChanged, identifiedUserId != nil else { return }
        // Staleness is judged in `acquireGateOrDefer`, atomically with acquisition; anything
        // decided here can be false by the time the replay takes the gate.
        Task { [weak self] in
            _ = await self?.handleMovement(
                latitude: pending.latitude, longitude: pending.longitude,
                anchorIsLiveFix: pending.anchorIsLiveFix, replaySequence: pending.sequence,
                heldFix: pending.heldFix
            )
        }
    }

    /// - Parameter replaySequence: a replay's original arrival sequence, or nil for a fresh movement.
    ///   Re-using it means being re-deferred cannot make stale coordinates look newest.
    func handleMovement(
        latitude: Double, longitude: Double, anchorIsLiveFix: Bool, replaySequence: UInt64?,
        heldFix: ResolvedFix?
    ) async -> Result<Void, GeofenceSyncError> {
        let sequence: UInt64
        switch acquireGateOrDefer(
            latitude: latitude, longitude: longitude,
            anchorIsLiveFix: anchorIsLiveFix, replaySequence: replaySequence, heldFix: heldFix
        ) {
        case .overtaken:
            logger.geofenceSyncSkipped(reason: .movementOvertaken)
            return .failure(.alreadyInProgress)
        case .deferred:
            logger.geofenceSyncSkipped(reason: .refreshInProgress)
            return .failure(.alreadyInProgress)
        case .taken(let taken):
            sequence = taken
        }
        let expectedUserId = identifiedUserId
        let outcome = await performMovement(
            expectedUserId: expectedUserId, latitude: latitude, longitude: longitude,
            anchorIsLiveFix: anchorIsLiveFix, heldFix: heldFix
        )
        // Keyed on the re-centre, not success, and noted before the release so a replay draining
        // off it compares against this pass.
        if outcome.reCentred { noteMovementApplied(sequence) }
        let cleaned = await cleanupIfUserChanged(expectedUserId: expectedUserId)
        releaseGate()
        if cleaned { retryForCurrentUser(latitude: latitude, longitude: longitude, anchorIsLiveFix: anchorIsLiveFix) }
        drainDeferredMovement(userChanged: cleaned)
        return outcome.result
    }

    /// Takes the gate, or records the movement for replay, in ONE critical section.
    ///
    /// In two steps the holder can release AND drain between a failed acquire and the record
    /// landing, leaving a record nothing will drain. Inside one section, either the holder's
    /// release drains the record or this call acquires the gate itself.
    ///
    /// Lock order is one-way: `refreshInProgress` then `deferredMovement`. `drainDeferredMovement`
    /// reads `deferredMovement` alone and replays outside the section.
    /// - Parameter replaySequence: a replay's original sequence, or nil for a fresh arrival. Fresh
    ///   arrivals are stamped here, not by the caller: minting before the gate lets a pass that
    ///   acquires later hold an earlier number, so a refresh taking the free gate meanwhile would
    ///   mark the live movement overtaken.
    func acquireGateOrDefer(
        latitude: Double, longitude: Double, anchorIsLiveFix: Bool, replaySequence: UInt64?,
        heldFix: ResolvedFix?
    ) -> GateOutcome {
        refreshInProgress.mutating { inProgress in
            // Only a replay can be overtaken; a fresh arrival is the newest by definition. Judged
            // inside the section because a newer movement can re-centre between an outside check
            // and the acquisition.
            if let replaySequence, appliedMovementSequence.wrappedValue >= replaySequence {
                return .overtaken
            }
            let sequence = replaySequence ?? nextMovementSequence()
            let movement = DeferredMovement(
                latitude: latitude, longitude: longitude,
                anchorIsLiveFix: anchorIsLiveFix, sequence: sequence, heldFix: heldFix
            )
            if inProgress {
                // Highest sequence wins, not last writer: a replay carries its original sequence
                // and can lose the gate after a newer arrival has queued.
                if (deferredMovement.wrappedValue?.sequence ?? 0) < movement.sequence {
                    deferredMovement.wrappedValue = movement
                }
                return .deferred
            }
            inProgress = true
            // A running pass supersedes an older queued one, which would otherwise replay after it
            // and move the trigger back. Cleared inside the section so a newer movement recording
            // itself meanwhile isn't wiped, and only when outranked: a replay can take a briefly
            // free gate while a newer arrival waits behind it.
            if (deferredMovement.wrappedValue?.sequence ?? 0) <= movement.sequence {
                deferredMovement.wrappedValue = nil
            }
            return .taken(sequence: sequence)
        }
    }

    /// Drops any queued movement and frees the gate in ONE critical section. In two steps a
    /// movement could queue itself after the clear, survive a reset, and later re-centre the
    /// trigger for the cleared profile.
    func discardDeferredAndReleaseGate() {
        refreshInProgress.mutating { inProgress in
            deferredMovement.wrappedValue = nil
            inProgress = false
        }
    }

    /// Takes the gate and stamps the pass with its arrival order, in ONE critical section.
    /// Allocating afterwards lets a movement arriving in the gap take a lower sequence than the
    /// holder, and then be retired as overtaken by older coordinates.
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
