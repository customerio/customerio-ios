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
        now: Date = Date(),
        reading: GeofenceClockReading? = nil
    ) -> PolygonMembershipOutcome {
        recordPolygonMembershipWrite(
            membership, forIdentifier: identifier, onlyIfBeliefPredates: evidenceTimestamp,
            onlyIfRingMatches: evaluatedRing, onlyIfCircleMatches: evaluatedCircle, now: now, reading: reading
        ).outcome
    }

    /// `recordPolygonMembership`, also returning when the belief it replaced or confirmed was last
    /// proven: for an outside belief its `lastChangedAt`, for an inside belief the last decisive
    /// inside proof (`lastDecisiveInsideAt`); a future stamp reads as `distantPast`, an absent one
    /// as nil. For an EXIT that is how recently the device was really known inside, which bounds
    /// how early it could have left. `decisiveInside` marks inside evidence that proved the stay on
    /// its own, which stamps that proof; a marginal arrival or confirmation does not. `reading` is
    /// the dwell clock read before the write, which places outside evidence on the monotonic
    /// timeline (`PolygonMembershipRecord.lastOutside`); nil places none.
    func recordPolygonMembershipWrite(
        _ membership: PolygonMembership,
        forIdentifier identifier: String,
        onlyIfBeliefPredates evidenceTimestamp: Date? = nil,
        onlyIfRingMatches evaluatedRing: [LocationData]? = nil,
        onlyIfCircleMatches evaluatedCircle: MonitoredCircle? = nil,
        decisiveInside: Bool = false,
        now: Date = Date(),
        reading: GeofenceClockReading? = nil
    ) -> PolygonMembershipWrite {
        // Clamped: a clock set backwards would stamp the belief in the future and refuse corrections.
        let evidenceTimestamp = evidenceTimestamp.map { min($0, now) }
        var state = loadFromDisk() ?? GeofenceState()
        // Checked in the writing call, as a refresh can land after the main-actor decision. The ring
        // itself, not `lastUpdated`, which a server replacement may not bump.
        guard Self.matchesEvaluatedGeometry(
            state: state, identifier: identifier,
            evaluatedRing: evaluatedRing, evaluatedCircle: evaluatedCircle
        ) else { return PolygonMembershipWrite(outcome: .suppressedGeometryChanged) }
        let currentRing = state.cachedGeofences?.first { $0.id == identifier }?.vertices
        var records = state.polygonMembership ?? [:]
        let existing = records[identifier]
        // A future stamp is discarded, not capped: capped at `now` it would outrank every real fix.
        let existingStamp = existing.map { $0.lastChangedAt > now ? Date.distantPast : $0.lastChangedAt }
        if let evidenceTimestamp, let existingStamp, existingStamp > evidenceTimestamp {
            return PolygonMembershipWrite(outcome: .suppressedNewerDecision)
        }
        let stamp = evidenceTimestamp ?? now
        let decisiveStamp = membership == .inside && decisiveInside ? stamp : nil
        let outsideStamp = membership == .outside ? reading.map { GeofenceClockStamp(date: stamp, at: $0) } : nil
        guard let existing else {
            // An evaluation in flight when the polygon was pruned would enter an unregistered fence.
            guard state.monitoredGeofenceIds?.contains(identifier) == true else {
                return PolygonMembershipWrite(outcome: .suppressedUnmonitored)
            }
            records[identifier] = PolygonMembershipRecord(
                membership: membership, lastChangedAt: stamp, ring: currentRing, lastDecisiveInsideAt: decisiveStamp,
                lastOutside: outsideStamp
            )
            state.polygonMembership = records
            saveToDisk(state)
            return PolygonMembershipWrite(outcome: membership == .inside ? .discoveredInside : .suppressedInitialOutside)
        }
        guard existing.membership != membership else {
            var confirmed = existing
            if let evidenceTimestamp, let existingStamp, evidenceTimestamp > existingStamp {
                confirmed.lastChangedAt = evidenceTimestamp
            }
            if let decisiveStamp, decisiveStamp > (existing.lastDecisiveInsideAt ?? .distantPast) {
                confirmed.lastDecisiveInsideAt = decisiveStamp
            }
            if let outsideStamp {
                confirmed.lastOutside = existing.lastOutside.map { $0.newer(outsideStamp) } ?? outsideStamp
            }
            // A confirmation under a replaced ring re-proves the belief against the new ring, so it
            // is re-stamped even when its evidence is no newer.
            confirmed.ring = currentRing
            if confirmed != existing {
                records[identifier] = confirmed
                state.polygonMembership = records
                saveToDisk(state)
            }
            return PolygonMembershipWrite(outcome: .suppressedNoChange, previousProvenAt: existingStamp)
        }
        // The last decisive inside proof, for the EXIT this write may deliver.
        let decisiveInsideProvenAt = existing.lastDecisiveInsideAt.map { $0 > now ? Date.distantPast : $0 }
        records[identifier] = PolygonMembershipRecord(
            membership: membership, lastChangedAt: stamp, ring: currentRing, lastDecisiveInsideAt: decisiveStamp,
            lastOutside: outsideStamp.map { existing.lastOutside?.newer($0) ?? $0 } ?? existing.lastOutside
        )
        state.polygonMembership = records
        saveToDisk(state)
        guard membership == .inside else {
            return PolygonMembershipWrite(outcome: .deliver(.exit), previousProvenAt: decisiveInsideProvenAt)
        }
        let observed = Self.observesEntry(
            from: existing, provenAt: existingStamp, insideAt: evidenceTimestamp, currentRing: currentRing
        )
        return PolygonMembershipWrite(outcome: observed ? .deliver(.enter) : .discoveredInside, previousProvenAt: existingStamp)
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

    /// Whether the cached catalog holds `id` as a polygon now.
    func isPolygon(id: String) async -> Bool {
        await runBeforeShapeRead()
        return loadFromDisk()?.cachedGeofences?.first { $0.id == id }?.vertices != nil
    }

    func getPolygonMembership() -> [String: PolygonMembershipRecord] {
        loadFromDisk()?.polygonMembership ?? [:]
    }

    /// What a polygon's covering-circle crossing is judged by, in one read: the polygon's stored
    /// dwell visit, and the evidence that the device was outside it, each placed on the monotonic
    /// timeline it was recorded on — the membership's latest outside proof, kept through any inside
    /// pass since (`PolygonMembershipRecord.lastOutside`), and the covering circle's last observed
    /// outside state, kept through the ENTER that replaced it (`MonitorRegionRecord.lastObservedOutside`)
    /// while that record is still this fence's circle.
    func polygonDepartureEvidence(geofenceId: String) -> (visit: GeofenceDwellVisit?, outside: [GeofenceClockStamp]) {
        let state = loadFromDisk()
        var outside = [state?.polygonMembership?[geofenceId]?.lastOutside].compactMap { $0 }
        if let record = state?.monitorRegionRecords?[geofenceId], let center = record.center, let radius = record.radius,
           let geofence = state?.cachedGeofences?.first(where: { $0.id == geofenceId }),
           // The registered radius as its own cap: a clamped covering circle still matches.
           MonitoredCircle(center: center, radius: radius, maximumRadius: radius).matches(geofence),
           let circleOutside = record.lastObservedOutside {
            outside.append(circleOutside)
        }
        return (state?.dwellVisits?[geofenceId], outside)
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
