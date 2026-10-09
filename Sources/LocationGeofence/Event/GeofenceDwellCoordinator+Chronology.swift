import Foundation

/// An EXIT, or a decisive outside fix that orders like one, as the coordinator processed it; or a
/// native ENTER, noted with the same ordering to tell a later crossing from a copy.
struct GeofenceExitMark: Equatable {
    /// What recorded the mark. Only an EXIT event is delivered, and may still be in flight to
    /// report the visit it ended; outside evidence ends a visit with no event of its own. A native
    /// ENTER is noted with the same ordering, in `enterMarks` only.
    enum Source: Equatable {
        case exitEvent
        case outsideEvidence
        case enterEvent
    }

    /// The date the OS or the fix stamped it with. For an EXIT event, also the event's identity:
    /// the same EXIT carries this exact date however late, or on whatever clock, it is read.
    let date: Date
    let source: Source
    /// `date` placed on the monotonic timeline at processing (`GeofenceVisitTiming.uptime(of:at:)`).
    let mappedUptime: TimeInterval
    /// The uptime it was processed at: the real order of processing, whatever the wall clock did.
    let processedUptime: TimeInterval
    /// `GeofenceClockReading.wallOffset` at processing.
    let wallOffset: TimeInterval

    init(date: Date, processedAt reading: GeofenceClockReading, source: Source) {
        self.date = date
        self.source = source
        self.mappedUptime = GeofenceVisitTiming.uptime(of: date, at: reading)
        self.processedUptime = reading.uptime
        self.wallOffset = reading.wallOffset
    }

    /// Whether this EXIT ends `visit`, or refuses its write.
    ///
    /// While the wall clock reads the same against uptime as when the visit was recorded, the two
    /// dates order them. Once it has stepped in between, a date taken before the step and mapped
    /// after it is off by the whole step, so the mapped order says nothing. The EXIT then counts if
    /// it was processed after the visit was recorded, or is dated no earlier than the visit's entry
    /// on whatever clock dated both. Either error ends a visit — a lost dwell — and none carries a
    /// stay across an EXIT. A visit with no timing cannot be ordered at all.
    func overtakes(_ visit: GeofenceDwellVisit) -> Bool {
        guard let timing = visit.timing else { return true }
        if abs(wallOffset - timing.wallOffset) <= GeofenceConstants.dwellWallClockStepTolerance {
            return mappedUptime >= timing.enteredUptime
        }
        return processedUptime >= timing.recordedUptime || date >= visit.enteredAt
    }

    /// For a native ENTER: whether it is a later crossing than the one `visit` began with, so the
    /// visit is not the stay it reports. A copy of the visit's own ENTER — dated within the
    /// tolerance of its entry — is not. Across a wall-clock step the dates cannot be ordered: the
    /// ENTER then counts as later when it was processed after the visit was recorded.
    func supersedes(_ visit: GeofenceDwellVisit) -> Bool {
        guard let timing = visit.timing else { return true }
        let tolerance = GeofenceConstants.dwellWallClockStepTolerance
        if abs(wallOffset - timing.wallOffset) <= tolerance {
            return mappedUptime > timing.enteredUptime + tolerance
        }
        return processedUptime > timing.recordedUptime
    }

    /// For a native ENTER already noted: whether it ends every visit `other` would, so `other`
    /// need not replace it. On one wall-clock timeline the later date is the later crossing,
    /// whichever was processed last — an older ENTER's routing re-notes it after a later ENTER's
    /// callback did. Across a step the dates do not order, so this one stays only if it was both
    /// processed and dated no earlier.
    func outranksEnter(_ other: GeofenceExitMark) -> Bool {
        if abs(wallOffset - other.wallOffset) <= GeofenceConstants.dwellWallClockStepTolerance {
            return mappedUptime >= other.mappedUptime
        }
        return processedUptime >= other.processedUptime && mappedUptime >= other.mappedUptime
    }

    /// Whether this mark overtakes every visit `other` does, which `other` then adds nothing to.
    /// Only on the same timeline: across a step, neither mark's dates order against the other's.
    /// Only of the same source, so outside evidence never stands in for an EXIT event, nor an EXIT
    /// for the outside evidence that withholds a duration.
    func subsumes(_ other: GeofenceExitMark) -> Bool {
        source == other.source
            && abs(wallOffset - other.wallOffset) < 0.001
            && mappedUptime >= other.mappedUptime
            && processedUptime >= other.processedUptime
            && date >= other.date
    }
}

/// The latest native ENTERs a fence has seen in this process: one a crossing, one not — an OS
/// correction of a state it assumed, or a baseline heal. Kept apart, so a correction noted after a
/// crossing cannot hide the crossing's end of an emitted stay.
struct GeofenceEnterMarks {
    var crossing: GeofenceExitMark?
    var correction: GeofenceExitMark?

    /// Whether these ENTERs end `visit`. A crossing ends any stay it is later than. A correction
    /// says the device is inside, not that it arrived again: it ends only a stay not yet qualified,
    /// which restarts at it, since nothing watched the time the OS assumed the device outside. A
    /// dwell already emitted or reserved stands, so the stay does not qualify a second time.
    func supersede(_ visit: GeofenceDwellVisit) -> Bool {
        !superseding(visit).isEmpty
    }

    /// The ENTERs that end `visit`, by the rule of `supersede`.
    func superseding(_ visit: GeofenceDwellVisit) -> [GeofenceExitMark] {
        var ending: [GeofenceExitMark] = []
        if let crossing, crossing.supersedes(visit) { ending.append(crossing) }
        if !visit.emitted, visit.dwellReservation == nil, let correction, correction.supersedes(visit) {
            ending.append(correction)
        }
        return ending
    }
}

/// A native EXIT callback the binder has handed to a routing task that has not finished, by its
/// exact date: the marks of its deliveries that no other subsumes, and how many deliveries are
/// still being routed. Until its routing records it, nothing else tells the coordinator the stay
/// may have ended.
struct GeofencePendingExitCallback {
    var marks: [GeofenceExitMark]
    var count: Int
    /// Whether routing recorded this EXIT, even if a later EXIT has since subsumed its mark.
    var recorded = false
}

/// Ordering boundary events against visits across wall-clock steps, split from the coordinator's
/// visit lifecycle so both stay under the file cap.
extension GeofenceDwellCoordinator {
    /// Reads `clock`, noting a wall-clock step since this coordinator's previous reading.
    func readClock() -> GeofenceClockReading {
        let reading = clock.read()
        let previousOffset = lastWallOffset ?? firstReading.wallOffset
        if abs(reading.wallOffset - previousOffset) > GeofenceConstants.dwellWallClockStepTolerance {
            wallStepSeenUptime = reading.uptime
        }
        lastWallOffset = reading.wallOffset
        return reading
    }

    /// Records an EXIT before any await, so an ENTER write already in flight sees it. Marks one
    /// subsumes are dropped, so on a steady clock a fence keeps one.
    func recordExit(_ mark: GeofenceExitMark, geofenceId: String) {
        var marks = exitMarks[geofenceId] ?? []
        guard !marks.contains(where: { $0.subsumes(mark) }) else { return }
        marks.removeAll { mark.subsumes($0) }
        marks.append(mark)
        exitMarks[geofenceId] = marks
    }

    /// Notes a native ENTER as the OS delivers it, ahead of any evidence its wake re-arms.
    /// `crossing` is the ENTER's `entryObserved`.
    func noteEnter(_ mark: GeofenceExitMark, geofenceId: String, crossing: Bool) {
        let slot: WritableKeyPath<GeofenceEnterMarks, GeofenceExitMark?> = crossing ? \.crossing : \.correction
        var marks = enterMarks[geofenceId] ?? GeofenceEnterMarks()
        if let noted = marks[keyPath: slot], noted.outranksEnter(mark) { return }
        marks[keyPath: slot] = mark
        enterMarks[geofenceId] = marks
    }

    /// Notes a native ENTER from the OS callback itself, before its routing task runs.
    func noteEnter(geofenceId: String, occurredAt: Date, crossing: Bool) {
        let mark = GeofenceExitMark(date: occurredAt, processedAt: readClock(), source: .enterEvent)
        noteEnter(mark, geofenceId: geofenceId, crossing: crossing)
    }

    /// Whether a native ENTER this process has seen ends `visit` (`GeofenceEnterMarks.supersede`).
    func enterSuperseded(_ visit: GeofenceDwellVisit, geofenceId: String) -> Bool {
        enterMarks[geofenceId]?.supersede(visit) ?? false
    }

    /// Whether an EXIT this process has seen for the fence ends `visit`.
    func exitOvertook(_ visit: GeofenceDwellVisit, geofenceId: String) -> Bool {
        exitMarks[geofenceId]?.contains { $0.overtakes(visit) } ?? false
    }

    /// Notes a native EXIT in the OS callback, before the binder re-arms evidence or starts the
    /// task that routes it. It is not an EXIT mark: a polygon's covering-circle EXIT may prove
    /// nothing, so it ends no visit. It only holds back a first DWELL while it is being routed
    /// (`exitCallbackPendingOvertook`). In OS order, it also keeps the native ENTERs noted so far,
    /// for timing this EXIT (`exitRoutingBegan`). The binder pairs it with `exitCallbackRouted` once
    /// that task is done, whatever it made of the EXIT; no time limit.
    func noteExitCallback(geofenceId: String, occurredAt: Date) {
        exitRoutingBegan(at: occurredAt, geofenceId: geofenceId)
        let mark = GeofenceExitMark(date: occurredAt, processedAt: readClock(), source: .exitEvent)
        var pending = pendingExitCallbacks[geofenceId]?[occurredAt] ?? GeofencePendingExitCallback(marks: [], count: 0)
        // As `recordExit` keeps them: across a clock step no delivery's mark orders the others, and a
        // later one can end fewer visits than an earlier one did.
        if !pending.marks.contains(where: { $0.subsumes(mark) }) {
            pending.marks.removeAll { mark.subsumes($0) }
            pending.marks.append(mark)
        }
        pending.count += 1
        pendingExitCallbacks[geofenceId, default: [:]][occurredAt] = pending
    }

    /// The routing task of an EXIT callback `noteExitCallback` noted has finished. Once no delivery
    /// of it is left, a visit remembered for an EXIT it never recorded is forgotten
    /// (`forgetUnrecordedExitCallback`), before its routing count is pruned.
    func exitCallbackRouted(geofenceId: String, occurredAt: Date) {
        if var pending = pendingExitCallbacks[geofenceId]?[occurredAt] {
            pending.count -= 1
            pendingExitCallbacks[geofenceId]?[occurredAt] = pending.count > 0 ? pending : nil
            if pendingExitCallbacks[geofenceId]?.isEmpty == true { pendingExitCallbacks[geofenceId] = nil }
            if pending.count <= 0, !pending.recorded { forgetUnrecordedExitCallback(at: occurredAt, geofenceId: geofenceId) }
        }
        exitRoutingEnded(at: occurredAt, geofenceId: geofenceId)
    }

    /// Whether a native EXIT callback still being routed would end `visit`, by the same order as a
    /// recorded EXIT: a late EXIT dated before the visit began does not.
    func exitCallbackPendingOvertook(_ visit: GeofenceDwellVisit, geofenceId: String) -> Bool {
        pendingExitCallbacks[geofenceId]?.values.contains { $0.marks.contains { $0.overtakes(visit) } } ?? false
    }

    /// Whether an entry dated `enteredAt`, recorded at `reading` with `timing`, was dated on the
    /// wall clock in force now. A date in the reading's future, or one placed before a step this
    /// coordinator has seen, may have been taken before the step: the visit it starts still counts
    /// time from when it was recorded, but its date is reportable against nothing.
    ///
    /// An entry dated before this coordinator's first reading — an event the OS raised before the
    /// process, or the coordinator, existed — is on the current clock only if an earlier process's
    /// persisted reference shows the same boot and wall offset as that first reading, and the entry
    /// is no older than the reference. Otherwise the clock may have stepped between the entry and
    /// the first reading, and nothing this process saw can tell.
    func entryIsOnCurrentClock(_ timing: GeofenceVisitTiming, enteredAt: Date, reading: GeofenceClockReading) -> Bool {
        let tolerance = GeofenceConstants.dwellWallClockStepTolerance
        guard enteredAt.timeIntervalSince(reading.wall) <= tolerance else { return false }
        if let wallStepSeenUptime, timing.enteredUptime < wallStepSeenUptime { return false }
        guard timing.enteredUptime < firstReading.uptime else { return true }
        guard let reference = clockReferenceAtLaunch,
              reference.boot.isSameBoot(as: firstReading.boot),
              abs(reference.wallOffset - firstReading.wallOffset) <= tolerance
        else { return false }
        return timing.enteredUptime >= reference.uptime
    }

    /// Loads the reference an earlier process left, once, then persists this process's clock
    /// whenever it differs from what is persisted: a new boot, or a wall-clock step.
    func syncClockReference(_ reading: GeofenceClockReading) async {
        if clockReferenceLoad == nil {
            let storage = storage
            clockReferenceLoad = Task { await storage.getClockReference() }
        }
        guard let load = clockReferenceLoad else { return }
        let launchReference = await load.value
        if persistedClockReference == nil {
            clockReferenceAtLaunch = launchReference
            persistedClockReference = launchReference
        }
        if let persisted = persistedClockReference, persisted.boot.isSameBoot(as: reading.boot),
           abs(persisted.wallOffset - reading.wallOffset) <= GeofenceConstants.dwellWallClockStepTolerance {
            return
        }
        persistedClockReference = reading
        await storage.setClockReference(reading)
    }
}
