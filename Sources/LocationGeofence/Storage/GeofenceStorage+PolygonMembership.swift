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
    /// device inside is therefore still owed an enter (the polygon counterpart of enter-when-inside),
    /// while a first fix placing it outside simply establishes the belief. That enter is
    /// `.discoveredInside`, not `.deliver(.enter)`: the device was never seen outside, so the stay
    /// was already in progress and its start is unknown. Only an `outside` belief stamped with the
    /// same ring and proven within `polygonOutsideProofMaxAge` before the inside evidence makes
    /// inside an observed crossing; an older one still flips the belief and delivers the ENTER, as
    /// `.discoveredInside`. Because the record survives re-registration, a
    /// wholesale re-register stays silent without needing a diff.
    ///
    /// `onlyIfBeliefPredates` makes the write conditional on the belief's age, atomically with the
    /// compare-and-store: an evaluation whose fix predates a belief written since must not
    /// overwrite it with an older reading. The stored `lastChangedAt` is that same evidence
    /// time, never later than the write — the comparison is evidence against evidence, and a write time
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
        // A crossing cannot postdate the moment we learn of it. Unclamped, a clock set backwards
        // stamps the belief in the future and every correcting write is refused until it catches up.
        let evidenceTimestamp = evidenceTimestamp.map { min($0, now) }
        var state = loadFromDisk() ?? GeofenceState()
        // Read and compared inside the same actor call that writes, because that is the only place
        // the two cannot be separated. The evaluation's own re-read closes the location request;
        // this closes what is left — deciding on the main actor and then hopping here to write, a
        // gap a refresh can land in. The ring itself, not `lastUpdated`: the server owns that field
        // and a replacement that failed to bump it would pass a check written against it.
        guard Self.matchesEvaluatedGeometry(
            state: state, identifier: identifier,
            evaluatedRing: evaluatedRing, evaluatedCircle: evaluatedCircle
        ) else { return .suppressedGeometryChanged }
        let currentRing = state.cachedGeofences?.first { $0.id == identifier }?.vertices
        var records = state.polygonMembership ?? [:]
        let existing = records[identifier]
        // A stamp ahead of `now` is impossible evidence — persisted by a build that predates the
        // clamp above, or written while the clock was ahead. Discarded, not capped: a real fix
        // always carries some age, so a stamp capped at `now` still outranks every one of them and
        // the belief stays unrepairable until the wall clock catches up.
        let existingStamp = existing.map { $0.lastChangedAt > now ? Date.distantPast : $0.lastChangedAt }
        if let evidenceTimestamp, let existingStamp, existingStamp > evidenceTimestamp {
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
        // A covering-circle exit carries no ring, but its verdict is only valid while this same
        // monitored circle belongs to the fence. Check inside the actor's compare-and-store.
        if let evaluatedCircle {
            guard let current, evaluatedCircle.matches(current) else { return false }
        }
        return true
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
