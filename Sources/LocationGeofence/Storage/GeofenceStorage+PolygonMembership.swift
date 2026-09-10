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
    /// Refreshing cannot suppress a queued covering-circle exit that is still owed: confirmation
    /// requires the belief to be true, so a stamp advanced past that exit's date means the device
    /// was inside the polygon — and polygon ⊆ circle, so inside the circle too, which makes the
    /// older exit genuinely superseded rather than lost.
    ///
    /// A confirming OUTSIDE is the case that needs the refresh most. It drops a later evaluation
    /// carrying an older INSIDE reading — correctly: the device was proven outside at the newer
    /// instant, so that reading describes a visit already over, and delivering its enter would park
    /// the belief at inside with no exit owed to bring it back. Without the refresh that stale
    /// enter clears the guard against the last CHANGE, and the polygon stays believed-inside until
    /// something else contradicts it.
    func recordPolygonMembership(
        _ membership: PolygonMembership,
        forIdentifier identifier: String,
        onlyIfBeliefPredates evidenceTimestamp: Date? = nil,
        onlyIfRingMatches evaluatedRing: [LocationData]? = nil,
        onlyIfCircleMatches evaluatedCircle: MonitoredCircle? = nil,
        now: Date = Date()
    ) -> PolygonMembershipOutcome {
        var state = loadFromDisk() ?? GeofenceState()
        // Read and compared inside the same actor call that writes, because that is the only place
        // the two cannot be separated. The evaluation's own re-read closes the location request;
        // this closes what is left — deciding on the main actor and then hopping here to write, a
        // gap a refresh can land in. The ring itself, not `lastUpdated`: the server owns that field
        // and a replacement that failed to bump it would pass a check written against it.
        if let evaluatedRing {
            let currentRing = state.cachedGeofences?.first { $0.id == identifier }?.vertices
            guard currentRing == evaluatedRing else { return .suppressedGeometryChanged }
        }
        // The covering exit's equivalent. It carries no ring — leaving a circle says nothing about
        // a ring — but the certainty it rests on is polygon ⊆ ITS OWN circle, so it holds only
        // while the fence still has the circle that was crossed. Checked here rather than before
        // the hop for the same reason as the ring: a refresh landing in between would otherwise
        // store `outside` for a device inside the replacement polygon.
        if let evaluatedCircle {
            guard let current = state.cachedGeofences?.first(where: { $0.id == identifier }),
                  evaluatedCircle.matches(current)
            else { return .suppressedGeometryChanged }
        }
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

    /// The cached fence for `id`, but only while it is still registered — both read from one load,
    /// so the geometry and the registration a verdict rests on cannot disagree with each other.
    /// A pass that sampled either before awaiting a fix must re-read through here afterwards.
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
    /// Drops polygon belief for geofences a registration no longer covers, on the same rule the
    /// monitor records use: a polygon outside the registered set is no longer being evaluated, so a
    /// retained belief would go stale and suppress the enter owed when the device comes back to it.
    mutating func prunePolygonState(retaining businessIds: Set<String>) {
        if let membership = polygonMembership {
            polygonMembership = membership.filter { businessIds.contains($0.key) }
        }
    }
}
