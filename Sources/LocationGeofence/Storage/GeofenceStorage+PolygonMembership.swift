import CioInternalCommon
import Foundation

extension GeofenceStorage {
    /// Atomic, so concurrent evaluations can't both deliver. No record means undecided: a first
    /// inside is an enter, a first outside only sets the belief. `lastChangedAt` is the evidence time,
    /// and a confirming evaluation refreshes it too, so older opposite evidence can't flip it.
    func recordPolygonMembership(
        _ membership: PolygonMembership,
        forIdentifier identifier: String,
        onlyIfBeliefPredates evidenceTimestamp: Date? = nil,
        onlyIfRingMatches evaluatedRing: [LocationData]? = nil,
        onlyIfCircleMatches evaluatedCircle: MonitoredCircle? = nil,
        now: Date = Date()
    ) -> PolygonMembershipOutcome {
        // Clamped: a clock set backwards would stamp the belief in the future and refuse corrections.
        let evidenceTimestamp = evidenceTimestamp.map { min($0, now) }
        var state = loadFromDisk() ?? GeofenceState()
        // Checked in the writing call, as a refresh can land after the main-actor decision. The ring
        // itself, not `lastUpdated`, which a server replacement may not bump.
        if let evaluatedRing {
            let currentRing = state.cachedGeofences?.first { $0.id == identifier }?.vertices
            guard currentRing == evaluatedRing else { return .suppressedGeometryChanged }
        }
        // A covering-circle exit proves leaving only while the fence still has the crossed circle.
        if let evaluatedCircle {
            guard let current = state.cachedGeofences?.first(where: { $0.id == identifier }),
                  evaluatedCircle.matches(current)
            else { return .suppressedGeometryChanged }
        }
        var records = state.polygonMembership ?? [:]
        let existing = records[identifier]
        // A future stamp is discarded, not capped: capped at `now` it would outrank every real fix.
        let existingStamp = existing.map { $0.lastChangedAt > now ? Date.distantPast : $0.lastChangedAt }
        if let evidenceTimestamp, let existingStamp, existingStamp > evidenceTimestamp {
            return .suppressedNewerDecision
        }
        guard let existing else {
            // An evaluation in flight when the polygon was pruned would enter an unregistered fence.
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

    /// One load, so both reads agree. A pass that sampled either before awaiting a fix must re-read.
    func getRegisteredGeofence(id: String) -> Geofence? {
        guard let state = loadFromDisk(), state.monitoredGeofenceIds?.contains(id) == true
        else { return nil }
        return state.cachedGeofences?.first { $0.id == id }
    }

    func getPolygonMembership() -> [String: PolygonMembershipRecord] {
        loadFromDisk()?.polygonMembership ?? [:]
    }
}

extension GeofenceState {
    /// A stale belief would suppress the enter owed when the device comes back.
    mutating func prunePolygonState(retaining businessIds: Set<String>) {
        if let membership = polygonMembership {
            polygonMembership = membership.filter { businessIds.contains($0.key) }
        }
    }
}
