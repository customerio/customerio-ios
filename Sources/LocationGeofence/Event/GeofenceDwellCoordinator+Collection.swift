import Foundation

/// Leases for the opt-in pending-dwell session, set and released synchronously as a visit's deadline
/// is armed and cancelled, so no stale storage read can drop a newer visit's lease. A lease only keeps
/// the process running; the deadline it serves still requests the usual fresh, strict proof.
extension GeofenceDwellCoordinator {
    /// The longest threshold the experiment collects for.
    static let collectedThresholdCeilingSeconds: TimeInterval = 7200
    /// How long past its threshold a visit's lease holds. Fixed: neither the retry spacing nor a
    /// re-arm extends it, so a longer spacing leaves later retries to wakes the OS grants anyway.
    static let collectionGraceSeconds: TimeInterval = 220

    /// From `init`. Weak, so the session never keeps this coordinator alive.
    func bindPendingDwellCollection() {
        let clock = self.clock
        pendingDwellCollection?.bind(
            now: { GeofenceDwellCoordinator.collectionNanoseconds(clock.read().uptime) ?? 0 },
            access: { [weak self] in self?.currentLocationAccess() },
            diagnosticRecorder: diagnosticRecorder,
            onActivity: { [weak self] in self?.reconcileCollection() }
        )
    }

    /// After `scheduleDeadline` armed `visit`: the fence's lease becomes this visit's, or none when it
    /// needs no acquisition. The cap depends only on the visit, so no re-arm can extend it.
    func armCollectionLease(for geofence: Geofence, visit: GeofenceDwellVisit, at reading: GeofenceClockReading) {
        guard let owner = pendingDwellCollection else { return }
        owner.set(collectionLease(for: geofence, visit: visit, at: reading), geofenceId: geofence.id)
        reconcileCollection()
    }

    func releaseCollectionLease(geofenceId: String, ifVisit visitId: String? = nil) {
        guard let owner = pendingDwellCollection else { return }
        owner.release(geofenceId: geofenceId, ifVisit: visitId)
        reconcileCollection()
    }

    /// Drops each lease whose visit a recorded loss, identity change, sign-out or access downgrade has
    /// already ended, then starts or stops the session. Re-arms no deadline and resets no retry budget.
    func reconcileCollection() {
        reconcileCollectionLeases { _, _ in true }
    }

    /// From a refresh, right after it persisted `geofences` and `registeredIds`: also drops the lease of a
    /// fence no longer registered or collected, or whose visit belongs to replaced geometry. Judged against
    /// what the refresh wrote, not a later read.
    func reconcileCollection(geofences: [Geofence], registeredIds: Set<String>) {
        rememberCatalog(geofences)
        // The first occurrence of a duplicated id decides, as every cache lookup does.
        let current = Dictionary(geofences.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ceiling = Self.collectedThresholdCeilingSeconds
        reconcileCollectionLeases { geofenceId, visit in
            guard registeredIds.contains(geofenceId), let geofence = current[geofenceId], geofence.vertices != nil,
                  geofence.dwellThresholdSeconds > 0, TimeInterval(geofence.dwellThresholdSeconds) <= ceiling
            else { return false }
            return visit.geometryRevision == geofence.dwellRevision
        }
    }

    /// Keeps a lease only while `holds` accepts it, its user is still the one signed in, and its visit's
    /// continuity holds. Synchronous: no lease set is replaced from an async read.
    private func reconcileCollectionLeases(also holds: (String, GeofenceDwellVisit) -> Bool) {
        guard let owner = pendingDwellCollection else { return }
        let userId = contextStore.currentUserId ?? ""
        owner.reconcile { geofenceId, visit in
            guard !userId.isEmpty, visit.userId == userId, holds(geofenceId, visit) else { return false }
            return continuityHolds(for: visit, geofenceId: geofenceId)
        }
    }

    private func collectionLease(
        for geofence: Geofence,
        visit: GeofenceDwellVisit,
        at reading: GeofenceClockReading
    ) -> PendingDwellCollectionOwner.Lease? {
        let threshold = TimeInterval(geofence.dwellThresholdSeconds)
        // A reserved dwell only repeats its delivery, and a candidate awaiting proof restarts as a new
        // visit once proven: neither needs a location to come due.
        guard geofence.vertices != nil, threshold > 0, threshold <= Self.collectedThresholdCeilingSeconds,
              !visit.emitted, visit.dwellReservation == nil, !visit.awaitsPresenceProof,
              visit.closedByObservedBoundary == nil,
              let timing = visit.timing, timing.bootRelation(at: reading) == .same
        else { return nil }
        guard let deadline = Self.collectionNanoseconds(timing.recordedUptime + threshold + Self.collectionGraceSeconds)
        else { return nil }
        return PendingDwellCollectionOwner.Lease(visit: visit, deadline: deadline)
    }

    /// Nil for a time no lease can hold: negative, non-finite, or beyond `UInt64` nanoseconds.
    nonisolated static func collectionNanoseconds(_ seconds: TimeInterval) -> UInt64? {
        let nanoseconds = seconds * 1000000000
        guard nanoseconds.isFinite, nanoseconds >= 0, nanoseconds < Double(UInt64.max) else { return nil }
        return UInt64(nanoseconds)
    }
}
