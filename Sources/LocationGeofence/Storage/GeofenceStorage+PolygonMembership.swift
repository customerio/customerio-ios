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
    /// overwrite it with an older reading.
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
            records[identifier] = PolygonMembershipRecord(membership: membership, lastChangedAt: now)
            state.polygonMembership = records
            saveToDisk(state)
            return membership == .inside ? .deliver(.enter) : .suppressedInitialOutside
        }
        guard existing.membership != membership else { return .suppressedNoChange }
        records[identifier] = PolygonMembershipRecord(membership: membership, lastChangedAt: now)
        state.polygonMembership = records
        saveToDisk(state)
        return .deliver(membership == .inside ? .enter : .exit)
    }

    /// Snapshot of every polygon membership belief.
    func getPolygonMembership() -> [String: PolygonMembershipRecord] {
        loadFromDisk()?.polygonMembership ?? [:]
    }

    /// Snapshot of every planted tripwire. Read when composing the OS-monitored set, so a tripwire
    /// survives the reconciliation that would otherwise sweep away a region nobody asked for.
    func getPolygonTripwires() -> [String: PolygonTripwire] {
        loadFromDisk()?.polygonTripwires ?? [:]
    }

    /// Plants or moves the tripwire for a polygon. Persisted before the OS registration so a sync
    /// racing the plant still finds it in the desired set.
    func setPolygonTripwire(_ tripwire: PolygonTripwire, forIdentifier identifier: String) {
        var state = loadFromDisk() ?? GeofenceState()
        var tripwires = state.polygonTripwires ?? [:]
        tripwires[identifier] = tripwire
        state.polygonTripwires = tripwires
        saveToDisk(state)
    }

    /// Removes the tripwire for a polygon, once the device has left its covering circle and the
    /// wake it provided is no longer needed. Returns whether anything was removed, so the caller
    /// can skip a re-registration that would change nothing.
    @discardableResult
    func clearPolygonTripwire(forIdentifier identifier: String) -> Bool {
        var state = loadFromDisk() ?? GeofenceState()
        guard var tripwires = state.polygonTripwires, tripwires.removeValue(forKey: identifier) != nil else { return false }
        state.polygonTripwires = tripwires
        saveToDisk(state)
        return true
    }
}

extension GeofenceState {
    /// Drops polygon belief and tripwires for geofences a registration no longer covers, on the
    /// same rule the monitor records use: a polygon outside the registered set is no longer being
    /// evaluated, so a retained belief would go stale and suppress the enter owed when the device
    /// comes back to it, and a retained tripwire would name a condition nothing plants.
    mutating func prunePolygonState(retaining businessIds: Set<String>) {
        if let membership = polygonMembership {
            polygonMembership = membership.filter { businessIds.contains($0.key) }
        }
        if let tripwires = polygonTripwires {
            polygonTripwires = tripwires.filter { businessIds.contains($0.key) }
        }
    }
}
