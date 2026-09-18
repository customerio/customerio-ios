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
            _ = await self?.handleMovement(
                latitude: pending.latitude, longitude: pending.longitude,
                anchorIsLiveFix: pending.anchorIsLiveFix
            )
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
