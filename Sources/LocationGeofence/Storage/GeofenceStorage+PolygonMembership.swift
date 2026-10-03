import CioInternalCommon
import Foundation

extension GeofenceStorage {
    /// Atomic, so concurrent evaluations can't both deliver. No record means undecided: a first
    /// inside is an owed enter, a first outside only sets the belief. `lastChangedAt` is the evidence
    /// time, and a confirming evaluation refreshes it too, so older opposite evidence can't flip it.
    ///
    /// An inside with no qualifying outside proof is `.discoveredInside`, not `.deliver(.enter)`: the
    /// ENTER is still owed, but the stay's start is unknown. Only an `outside` belief on the same ring,
    /// proven within `polygonOutsideProofMaxAge` before the inside evidence, makes it a crossing.
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
        guard Self.matchesEvaluatedGeometry(
            state: state, identifier: identifier,
            evaluatedRing: evaluatedRing, evaluatedCircle: evaluatedCircle
        ) else { return .suppressedGeometryChanged }
        let currentRing = state.cachedGeofences?.first { $0.id == identifier }?.vertices
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
                membership: membership, lastChangedAt: evidenceTimestamp ?? now, ring: currentRing
            )
            state.polygonMembership = records
            saveToDisk(state)
            return membership == .inside ? .discoveredInside : .suppressedInitialOutside
        }
        guard existing.membership != membership else {
            var confirmed = existing
            if let evidenceTimestamp, let existingStamp, evidenceTimestamp > existingStamp {
                confirmed.lastChangedAt = evidenceTimestamp
            }
            // A confirmation under a replaced ring re-proves the belief against the new ring, so it
            // is re-stamped even when its evidence is no newer.
            confirmed.ring = currentRing
            if confirmed != existing {
                records[identifier] = confirmed
                state.polygonMembership = records
                saveToDisk(state)
            }
            return .suppressedNoChange
        }
        records[identifier] = PolygonMembershipRecord(
            membership: membership, lastChangedAt: evidenceTimestamp ?? now, ring: currentRing
        )
        state.polygonMembership = records
        saveToDisk(state)
        guard membership == .inside else { return .deliver(.exit) }
        let observed = Self.observesEntry(
            from: existing, provenAt: existingStamp, insideAt: evidenceTimestamp, currentRing: currentRing
        )
        return observed ? .deliver(.enter) : .discoveredInside
    }

    /// Whether `outside` → inside is an observed crossing: only when the outside belief was formed
    /// against the ring the inside verdict is judged by, AND was last proven shortly before it.
    ///
    /// The time bound is what makes the entry's date meaningful. An outside belief from hours ago
    /// says the crossing happened at some point since, not that it happened at the inside fix, so
    /// reporting that fix as `entered_at` would be a guess. Every unknown fails closed: no inside
    /// evidence time, a stored stamp discarded as future (`provenAt` is then `distantPast`), or
    /// proof not strictly older than the inside fix. Records written by earlier builds carry
    /// whatever stamp they held — at worst the last change rather than the last confirmation,
    /// which is older, so it can only demote an entry, never promote one.
    private static func observesEntry(
        from outside: PolygonMembershipRecord,
        provenAt: Date?,
        insideAt: Date?,
        currentRing: [LocationData]?
    ) -> Bool {
        guard let ring = outside.ring, ring == currentRing else { return false }
        guard let provenAt, let insideAt, provenAt < insideAt else { return false }
        return insideAt.timeIntervalSince(provenAt) <= GeofenceConstants.polygonOutsideProofMaxAge
    }

    private static func matchesEvaluatedGeometry(
        state: GeofenceState,
        identifier: String,
        evaluatedRing: [LocationData]?,
        evaluatedCircle: MonitoredCircle?
    ) -> Bool {
        let current = state.cachedGeofences?.first { $0.id == identifier }
        if let evaluatedRing, current?.vertices != evaluatedRing { return false }
        // A covering-circle exit proves leaving only while the fence still has the crossed circle.
        if let evaluatedCircle {
            guard let current, evaluatedCircle.matches(current) else { return false }
        }
        return true
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
