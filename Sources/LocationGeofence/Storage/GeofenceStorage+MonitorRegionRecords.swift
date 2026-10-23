import CioInternalCommon
import Foundation

// MARK: - Monitor Region Records (CLMonitor path)

extension GeofenceStorage {
    /// The baseline is preserved on a re-register with unchanged geometry, so a CLMonitor
    /// re-evaluation isn't a duplicate. `forceReseed` after the OS stopped monitoring: the device may
    /// have crossed meanwhile. `initialStateObserved`: a fix settled `initialState` rather than it
    /// being assumed; see `MonitorRegionRecord.lastStateObserved`. Preserved with the baseline.
    func recordMonitorRegistration(
        identifier: String,
        transitionTypes: Set<GeofenceTransition>,
        initialState: GeofenceTransition,
        center: LocationData,
        radius: Double,
        forceReseed: Bool = false,
        initialStateObserved: Bool = false,
        now: Date? = nil // nil rather than `Date()`: a default expression cannot reach `dateUtil`.
    ) {
        var state = loadFromDisk() ?? GeofenceState()
        var records = state.monitorRegionRecords ?? [:]
        let existing = records[identifier]
        let unchangedGeometry = existing?.center == center && existing?.radius == radius
        let preserved = unchangedGeometry && !forceReseed
        let stamp = now ?? dateUtil.now
        records[identifier] = MonitorRegionRecord(
            lastState: preserved ? (existing?.lastState ?? initialState) : initialState,
            transitionTypes: transitionTypes,
            center: center,
            radius: radius,
            lastStateChangedAt: preserved ? existing?.lastStateChangedAt : stamp,
            // An OS event dated before this was computed against the old circle (see `recordMonitorEvent`).
            registeredAt: preserved ? existing?.registeredAt : stamp,
            // The trigger keeps its identity across radius changes, so its OS event dedup survives.
            lastEventDate: (preserved || identifier == GeofenceConstants.movementTriggerIdentifier) ? existing?.lastEventDate : nil,
            lastStateObserved: preserved ? existing?.lastStateObserved : initialStateObserved,
            // Of the same circle only: a changed one's outside says nothing about the new one.
            lastObservedOutside: preserved ? existing?.lastObservedOutside : nil
        )
        state.monitorRegionRecords = records
        saveToDisk(state)
    }

    /// The baseline advances on filtered transitions too, so an exit-only region sees the next exit
    /// as a change. `osEventDate` is judged against OS-dated history only, never SDK write times.
    func recordMonitorEvent(
        _ transition: GeofenceTransition,
        forIdentifier identifier: String,
        onlyIfBaselinePredates evidenceTimestamp: Date? = nil,
        osEventDate: Date? = nil,
        now: Date? = nil,
        processedAt reading: GeofenceClockReading? = nil,
        maximumRadius: Double = .infinity
    ) -> GeofenceMonitorEventOutcome {
        recordMonitorTransition(
            transition, forIdentifier: identifier,
            onlyIfBaselinePredates: evidenceTimestamp, osEventDate: osEventDate, now: now,
            processedAt: reading, maximumRadius: maximumRadius
        ).outcome
    }

    /// `recordMonitorEvent`, also answering whether a delivered transition left an OBSERVED state.
    /// Only then is it a crossing timed by its event: out of an assumed state it may be `CLMonitor`
    /// correcting its `assuming:` — an ENTER for a device that never left, an EXIT for one that was
    /// never inside or left at some unknown earlier time. False for every other outcome.
    /// - Parameter reading: when the producer read the dwell clock before this call; with it, a
    ///   delivered change also closes the circle visit it ends, in the same write (`closeVisit`).
    /// - Parameter maximumRadius: the radius cap the monitor registered the circle under.
    /// - Parameter raisedUnder: the generation the producer attributed the event to, if any; see
    ///   `outcome(ofEventRaisedUnder:)`.
    func recordMonitorTransition(
        _ transition: GeofenceTransition,
        forIdentifier identifier: String,
        onlyIfBaselinePredates evidenceTimestamp: Date? = nil,
        osEventDate: Date? = nil,
        now: Date? = nil,
        processedAt reading: GeofenceClockReading? = nil,
        maximumRadius: Double = .infinity,
        raisedUnder: GeofenceEventCircle? = nil
    ) -> (outcome: GeofenceMonitorEventOutcome, crossingObserved: Bool) {
        var state = loadFromDisk() ?? GeofenceState()
        var records = state.monitorRegionRecords ?? [:]
        guard var record = records[identifier] else {
            // Condition predates this bookkeeping. Silent, like classic registration's initial state.
            let seeded = MonitorRegionRecord(
                lastState: transition, transitionTypes: [.enter, .exit], lastStateChangedAt: now ?? dateUtil.now,
                lastEventDate: osEventDate, lastStateObserved: true
            )
            saveMonitorRecord(seeded, forIdentifier: identifier, in: &state)
            return (.suppressedNoBaseline, false)
        }
        if let outcome = outcome(ofEventRaisedUnder: raisedUnder, transition, record: record, osEventDate: osEventDate, evidenceTimestamp: evidenceTimestamp) { return (outcome, false) }
        let delayedMovementExit = Self.isDelayedMovementExit(
            transition, identifier: identifier, osEventDate: osEventDate, record: record
        )
        if let refused = Self.refusedByDate(
            &record, osEventDate: osEventDate, evidenceTimestamp: evidenceTimestamp,
            delayedMovementExit: delayedMovementExit, now: dateUtil.now
        ) {
            return (refused, false)
        }
        if delayedMovementExit {
            // Keep the new circle's seeded state, or its next real exit would look unchanged.
            saveMonitorRecord(record, forIdentifier: identifier, in: &state)
            return (record.transitionTypes.contains(transition) ? .deliver : .suppressedFilteredType, false)
        }
        guard record.lastState != transition else {
            // Persist the date so a later copy is refused.
            if osEventDate != nil {
                saveMonitorRecord(record, forIdentifier: identifier, in: &state)
            }
            // Not an observation of an assumed state: `CLMonitor` may just be echoing `assuming:`.
            return (.suppressedNoChange, false)
        }
        let leftObservedState = record.lastStateObserved ?? false
        if transition == .exit, let reading {
            record.lastObservedOutside = GeofenceClockStamp(date: now ?? dateUtil.now, at: reading)
        }
        record.lastState = transition
        record.lastStateChangedAt = now ?? dateUtil.now
        record.lastStateObserved = true
        records[identifier] = record
        state.monitorRegionRecords = records
        let delivered = record.transitionTypes.contains(transition)
        let crossing = transition == .enter && leftObservedState
        if delivered, let reading, transition == .exit || crossing, let center = record.center, let radius = record.radius {
            Self.closeVisit(in: &state, identifier: identifier, registered: MonitoredCircle(center: center, radius: radius, maximumRadius: maximumRadius), endedBy: transition, mark: GeofenceExitMark(date: osEventDate ?? now ?? dateUtil.now, processedAt: reading, source: transition == .exit ? .exitEvent : .enterEvent))
        }
        saveToDisk(state)
        return (delivered ? .deliver : .suppressedFilteredType, leftObservedState)
    }

    /// Writes `record` as `identifier`'s monitor record into `state`, and saves it.
    private func saveMonitorRecord(_ record: MonitorRegionRecord, forIdentifier identifier: String, in state: inout GeofenceState) {
        var records = state.monitorRegionRecords ?? [:]
        records[identifier] = record
        state.monitorRegionRecords = records
        saveToDisk(state)
    }

    /// A trigger exit can arrive just after a re-plant, carrying the old circle's date. Only the
    /// untouched re-plant baseline is exempt; later evidence keeps the ordering guard.
    private static func isDelayedMovementExit(
        _ transition: GeofenceTransition,
        identifier: String,
        osEventDate: Date?,
        record: MonitorRegionRecord
    ) -> Bool {
        guard identifier == GeofenceConstants.movementTriggerIdentifier, transition == .exit,
              let osEventDate, let registeredAt = record.registeredAt,
              let changedAt = record.lastStateChangedAt
        else { return false }
        return osEventDate < registeredAt && changedAt == registeredAt
    }

    func getMonitorRegionRecords() -> [String: MonitorRegionRecord] {
        loadFromDisk()?.monitorRegionRecords ?? [:]
    }

    /// Polygon belief deliberately SURVIVES: dropping it would re-deliver an enter for a device that
    /// stayed inside.
    func clearMonitorRegionRecord(identifier: String) {
        var state = loadFromDisk() ?? GeofenceState()
        guard state.monitorRegionRecords?.removeValue(forKey: identifier) != nil else { return }
        saveToDisk(state)
    }
}

/// The OS-date guards of `recordMonitorTransition`; same file, so they stay private.
extension GeofenceStorage {
    /// The outcome an event's dates alone decide, nil when they pass; a passing OS date is recorded
    /// on `record` as seen. Judged against OS-dated history only, never SDK write times.
    private static func refusedByDate(
        _ record: inout MonitorRegionRecord,
        osEventDate: Date?,
        evidenceTimestamp: Date?,
        delayedMovementExit: Bool,
        now: Date
    ) -> GeofenceMonitorEventOutcome? {
        if let osEventDate {
            if !delayedMovementExit,
               let registeredAt = stamp(record.registeredAt, ordering: osEventDate, now: now),
               osEventDate < registeredAt { return .suppressedPredatesRegistration }
            if let lastEventDate = stamp(record.lastEventDate, ordering: osEventDate, now: now),
               osEventDate <= lastEventDate { return .suppressedRedelivery }
            record.lastEventDate = osEventDate
        }
        if !delayedMovementExit, let evidenceTimestamp,
           let changedAt = stamp(record.lastStateChangedAt, ordering: evidenceTimestamp, now: now),
           changedAt > evidenceTimestamp {
            return .suppressedNewerBaseline
        }
        return nil
    }

    /// `stamp`, unless it cannot order `eventDate`: a stamp after `now` was written before the wall
    /// clock was set back, and an event dated on the clock as it reads now is not older than it,
    /// only on a different timeline. Kept against an event dated in that same future, which a copy
    /// from before the change is.
    private static func stamp(_ stamp: Date?, ordering eventDate: Date, now: Date) -> Date? {
        guard let stamp, stamp > now, eventDate <= now else { return stamp }
        return nil
    }
}

/// Same file as `refusedByDate`, which it shares.
extension GeofenceStorage {
    /// For an event raised under another circle than `record` now holds — the replaced generation,
    /// still live while the replacing one's record is already written — or under a generation known
    /// gone: what it would have been delivered as, judged on a copy. It never advances the record,
    /// whose baseline belongs to the replacing circle and dedups that circle's own events, and
    /// closes no visit. Nil for an event of the record's own circle, or of no recorded generation.
    private func outcome(
        ofEventRaisedUnder raisedUnder: GeofenceEventCircle?,
        _ transition: GeofenceTransition,
        record: MonitorRegionRecord,
        osEventDate: Date?,
        evidenceTimestamp: Date?
    ) -> GeofenceMonitorEventOutcome? {
        switch raisedUnder {
        case .circle(let raised):
            guard let center = record.center, let radius = record.radius,
                  !MonitoredCircle(center: center, radius: radius, maximumRadius: raised.maximumRadius).isSameCircle(as: raised)
            else { return nil }
        case .expired:
            break
        case .unknown, nil:
            return nil
        }
        var probe = record
        if let refused = Self.refusedByDate(&probe, osEventDate: osEventDate, evidenceTimestamp: evidenceTimestamp, delayedMovementExit: false, now: dateUtil.now) {
            return refused
        }
        guard probe.lastState != transition else { return .suppressedNoChange }
        return probe.transitionTypes.contains(transition) ? .deliver : .suppressedFilteredType
    }
}
