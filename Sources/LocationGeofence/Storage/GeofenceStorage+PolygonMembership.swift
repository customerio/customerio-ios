import CioInternalCommon
import Foundation

/// Polygon membership persistence, split out to keep `GeofenceStorage` readable. Methods are
/// `internal` (not `private`) only because they live in a separate file from their state; they
/// remain storage implementation detail.
extension GeofenceStorage {
    /// Records what an evaluation established about a polygon and returns whether it is a crossing.
    /// The whole compare-and-store runs inside the actor with no `await` between steps, so two
    /// concurrent evaluations cannot both observe a stale belief and both deliver.
    ///
    /// A polygon with no record yet is undecided, not outside: the first decisive fix placing the
    /// device inside is therefore a genuine enter (the polygon counterpart of enter-when-inside),
    /// while a first fix placing it outside simply establishes the belief. Because the record
    /// survives re-registration, a wholesale re-register stays silent without needing a diff.
    ///
    /// `onlyIfBeliefPredates` makes the write conditional on the belief's age, atomically with the
    /// compare-and-store: an evaluation whose fix predates a belief written since must not
    /// overwrite it with an older reading. The stored `lastChangedAt` is that same evidence time,
    /// not the moment of the write — the comparison is evidence against evidence, and a write time
    /// always postdates the fix that justified it, so storing it would reject verdicts whose
    /// evidence is genuinely newer than the previous verdict's.
    ///
    /// An evaluation that CONFIRMS the belief refreshes that stamp too. Re-proving a belief is
    /// newer evidence for it, and holding the stamp at the last change would let a later evaluation
    /// carrying older opposite evidence pass the guard and flip what a newer fix just confirmed.
    func recordPolygonMembership(
        _ membership: PolygonMembership,
        forIdentifier identifier: String,
        onlyIfBeliefPredates evidenceTimestamp: Date? = nil,
        now: Date = Date()
    ) -> PolygonMembershipOutcome {
        var state = loadFromDisk() ?? GeofenceState()
        var records = state.polygonMembership ?? [:]
        let existing = records[identifier]
        if let evidenceTimestamp, let existing, existing.lastChangedAt > evidenceTimestamp {
            return .suppressedNewerDecision
        }
        guard let existing else {
            // An evaluation in flight when the polygon was pruned would otherwise create a belief —
            // and an enter — for a fence no longer registered. Only the create path needs this: an
            // existing record means it was registered when the belief was formed, and pruning
            // removes it.
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
            if let evidenceTimestamp, evidenceTimestamp > existing.lastChangedAt {
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

    /// Snapshot of every polygon membership belief.
    func getPolygonMembership() -> [String: PolygonMembershipRecord] {
        loadFromDisk()?.polygonMembership ?? [:]
    }
}

extension GeofenceState {
    /// Drops one identifier's belief, for a reseed that has already decided the stored circle
    /// baseline can no longer be trusted: kept, a belief of "inside" formed before an unmonitored
    /// gap swallows the next real enter as no-change.
    mutating func dropPolygonBelief(for identifier: String) {
        polygonMembership?.removeValue(forKey: identifier)
    }

    /// Drops polygon belief for geofences a registration no longer covers, on the same rule the
    /// monitor records use: a polygon outside the registered set is no longer being evaluated, so a
    /// retained belief would go stale and suppress the enter owed when the device comes back to it.
    mutating func prunePolygonState(retaining businessIds: Set<String>) {
        if let membership = polygonMembership {
            polygonMembership = membership.filter { businessIds.contains($0.key) }
        }
    }
}
