import CioInternalCommon
import Foundation

extension GeofenceSyncCoordinatorImpl {
    struct DeferredMovement {
        let latitude: Double
        let longitude: Double
        let anchorIsLiveFix: Bool
        let sequence: UInt64
        /// Ages while the holder runs; the resolver requests a new fix past `movementFixMaxAge`.
        let heldFix: ResolvedFix?
    }

    /// `reCentred` is separate from `result`: a failed remote refresh can still re-arm from cache.
    struct MovementPassOutcome {
        let result: Result<Void, GeofenceSyncError>
        let reCentred: Bool
    }

    enum GateOutcome: Equatable {
        case taken(sequence: UInt64)
        case deferred
        case overtaken
    }

    func nextMovementSequence() -> UInt64 {
        movementSequence.mutating { value in
            value += 1
            return value
        }
    }

    /// Monotonic: passes complete out of order. Only pass sequences from `nextMovementSequence`, or
    /// `acquireGateOrDefer` can refuse real movements as overtaken.
    func noteMovementApplied(_ sequence: UInt64) {
        appliedMovementSequence.mutating { value in
            value = max(value, sequence)
        }
    }

    /// After an identity-change cleanup nothing is monitored, and the new user's own refresh may have
    /// been dropped on the gate this operation held.
    func retryForCurrentUser(latitude: Double, longitude: Double, anchorIsLiveFix: Bool) {
        guard identifiedUserId != nil else { return }
        Task { [weak self] in
            _ = await self?.refresh(
                latitude: latitude, longitude: longitude, anchorIsLiveFix: anchorIsLiveFix
            )
        }
    }

    /// Taken and cleared in one step, so a movement deferred during the replay isn't lost or replayed
    /// twice. Dropped on a user change: the coordinates belong to the old profile.
    func drainDeferredMovement(userChanged: Bool) {
        let pending = deferredMovement.mutating { value -> DeferredMovement? in
            defer { value = nil }
            return value
        }
        guard let pending, !userChanged, identifiedUserId != nil else { return }
        // Don't check staleness here; only `acquireGateOrDefer` can judge it atomically.
        Task { [weak self] in
            _ = await self?.handleMovement(
                latitude: pending.latitude, longitude: pending.longitude,
                anchorIsLiveFix: pending.anchorIsLiveFix, replaySequence: pending.sequence,
                heldFix: pending.heldFix
            )
        }
    }

    /// - Parameter replaySequence: a replay's original sequence, so re-deferral can't make stale
    ///   coordinates look newest. Nil for a fresh movement.
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
        // On re-centre, not success; before the release so a draining replay compares against it.
        if outcome.reCentred { noteMovementApplied(sequence) }
        let cleaned = await cleanupIfUserChanged(expectedUserId: expectedUserId)
        releaseGate()
        if cleaned { retryForCurrentUser(latitude: latitude, longitude: longitude, anchorIsLiveFix: anchorIsLiveFix) }
        drainDeferredMovement(userChanged: cleaned)
        return outcome.result
    }

    /// ONE critical section: in two steps the holder can release and drain between a failed acquire
    /// and the record, stranding it. Lock order: `refreshInProgress`, then `deferredMovement`.
    /// Fresh arrivals are stamped here: minting before the gate lets a later acquirer hold an
    /// earlier number and be marked overtaken.
    func acquireGateOrDefer(
        latitude: Double, longitude: Double, anchorIsLiveFix: Bool, replaySequence: UInt64?,
        heldFix: ResolvedFix?
    ) -> GateOutcome {
        refreshInProgress.mutating { inProgress in
            if let replaySequence, appliedMovementSequence.wrappedValue >= replaySequence {
                return .overtaken
            }
            let sequence = replaySequence ?? nextMovementSequence()
            let movement = DeferredMovement(
                latitude: latitude, longitude: longitude,
                anchorIsLiveFix: anchorIsLiveFix, sequence: sequence, heldFix: heldFix
            )
            if inProgress {
                // Highest sequence wins: a replay can lose the gate after a newer arrival queued.
                if (deferredMovement.wrappedValue?.sequence ?? 0) < movement.sequence {
                    deferredMovement.wrappedValue = movement
                }
                return .deferred
            }
            inProgress = true
            // Drop an older queued pass so it can't replay after this one; a replay can take the
            // gate while a newer arrival waits, so keep that one.
            if (deferredMovement.wrappedValue?.sequence ?? 0) <= movement.sequence {
                deferredMovement.wrappedValue = nil
            }
            return .taken(sequence: sequence)
        }
    }

    /// ONE critical section, or a movement queued after the clear would survive the reset.
    func discardDeferredAndReleaseGate() {
        refreshInProgress.mutating { inProgress in
            deferredMovement.wrappedValue = nil
            inProgress = false
        }
    }

    /// Stamps in the same section: stamping after lets a movement in the gap take a lower sequence
    /// than the holder and be retired as overtaken.
    func acquireGateWithSequence() -> UInt64? {
        refreshInProgress.mutating { inProgress in
            if inProgress { return nil }
            inProgress = true
            return nextMovementSequence()
        }
    }

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
