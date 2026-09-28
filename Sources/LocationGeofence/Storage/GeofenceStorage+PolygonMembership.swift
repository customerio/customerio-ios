import CioInternalCommon
import Foundation

/// Polygon membership persistence, split out of `GeofenceStorage.swift`.
extension GeofenceStorage {
    /// Records what an evaluation established about a polygon and returns whether it is a crossing,
    /// atomically, so concurrent evaluations can't both deliver.
    ///
    /// No record yet means undecided, not outside: a first inside is an enter, a first outside just
    /// sets the belief. The record survives re-registration, so a re-register stays silent.
    ///
    /// `onlyIfBeliefPredates` refuses evidence older than the stored belief. `lastChangedAt` stores
    /// the evidence (fix) time, not the write time, so newer evidence is never rejected.
    ///
    /// A confirming evaluation refreshes the stamp too, so older opposite evidence can't flip what a
    /// newer fix just confirmed (e.g. a stale inside after a proven outside would park the belief at
    /// inside with no exit owed). This can't swallow an owed covering-circle exit: a confirmed
    /// inside means inside the circle too, since polygon ⊆ circle.
    func recordPolygonMembership(
        _ membership: PolygonMembership,
        forIdentifier identifier: String,
        onlyIfBeliefPredates evidenceTimestamp: Date? = nil,
        onlyIfRingMatches evaluatedRing: [LocationData]? = nil,
        onlyIfCircleMatches evaluatedCircle: MonitoredCircle? = nil,
        now: Date = Date()
    ) -> PolygonMembershipOutcome {
        // A crossing cannot postdate the moment we learn of it. Unclamped, a clock set backwards
        // stamps the belief in the future and every correcting write is refused until it catches up.
        let evidenceTimestamp = evidenceTimestamp.map { min($0, now) }
        var state = loadFromDisk() ?? GeofenceState()
        // Compared in the same actor call that writes, closing the gap between deciding on the main
        // actor and writing here, where a refresh can land. The ring itself, not `lastUpdated`: a
        // server replacement that failed to bump that field would pass.
        if let evaluatedRing {
            let currentRing = state.cachedGeofences?.first { $0.id == identifier }?.vertices
            guard currentRing == evaluatedRing else { return .suppressedGeometryChanged }
        }
        // The covering-circle exit's equivalent: its certainty rests on polygon ⊆ the circle that
        // was crossed, so it holds only while the fence still has that circle.
        if let evaluatedCircle {
            guard let current = state.cachedGeofences?.first(where: { $0.id == identifier }),
                  evaluatedCircle.matches(current)
            else { return .suppressedGeometryChanged }
        }
        var records = state.polygonMembership ?? [:]
        let existing = records[identifier]
        // A stamp ahead of `now` (written while the clock was ahead, or before the clamp above) is
        // discarded, not capped: capped at `now` it would still outrank every real fix.
        let existingStamp = existing.map { $0.lastChangedAt > now ? Date.distantPast : $0.lastChangedAt }
        if let evidenceTimestamp, let existingStamp, existingStamp > evidenceTimestamp {
            return .suppressedNewerDecision
        }
        guard let existing else {
            // An evaluation in flight when the polygon was pruned would otherwise create a belief,
            // and an enter, for an unregistered fence. Pruning removes existing records.
            guard state.monitoredGeofenceIds?.contains(identifier) == true else {
                return .suppressedUnmonitored
            }
            records[identifier] = PolygonMembershipRecord(
                membership: membership, lastChangedAt: evidenceTimestamp ?? now
            )
            state.polygonMembership = records
            saveToDisk(state)
            return membership == .inside ? .deliver(.enter) : .suppressedInitialOutside
        }
        guard existing.membership != membership else {
            if let evidenceTimestamp, let existingStamp, evidenceTimestamp > existingStamp {
                records[identifier] = PolygonMembershipRecord(
                    membership: membership, lastChangedAt: evidenceTimestamp
                )
                state.polygonMembership = records
                saveToDisk(state)
            }
            return .suppressedNoChange
        }
        records[identifier] = PolygonMembershipRecord(
            membership: membership, lastChangedAt: evidenceTimestamp ?? now
        )
        state.polygonMembership = records
        saveToDisk(state)
        return .deliver(membership == .inside ? .enter : .exit)
    }

    /// The cached fence for `id`, only while it is still registered, read from one load so the two
    /// agree. A pass that sampled either before awaiting a fix must re-read through here.
    func getRegisteredGeofence(id: String) -> Geofence? {
        guard let state = loadFromDisk(), state.monitoredGeofenceIds?.contains(id) == true
        else { return nil }
        return state.cachedGeofences?.first { $0.id == id }
    }

    /// Snapshot of every polygon membership belief.
    func getPolygonMembership() -> [String: PolygonMembershipRecord] {
        loadFromDisk()?.polygonMembership ?? [:]
    }
}

extension GeofenceState {
    /// Drops polygon belief for geofences no longer registered; a stale belief would suppress the
    /// enter owed when the device comes back.
    mutating func prunePolygonState(retaining businessIds: Set<String>) {
        if let membership = polygonMembership {
            polygonMembership = membership.filter { businessIds.contains($0.key) }
        }
    }
}
