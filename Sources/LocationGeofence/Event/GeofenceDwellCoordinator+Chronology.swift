import Foundation

/// An EXIT, or a decisive outside fix that orders like one, as the coordinator processed it.
struct GeofenceExitMark: Equatable {
    /// The date the OS or the fix stamped it with.
    let date: Date
    /// `date` placed on the monotonic timeline at processing (`GeofenceVisitTiming.uptime(of:at:)`).
    let mappedUptime: TimeInterval
    /// The uptime it was processed at: the real order of processing, whatever the wall clock did.
    let processedUptime: TimeInterval
    /// `GeofenceClockReading.wallOffset` at processing.
    let wallOffset: TimeInterval

    init(date: Date, processedAt reading: GeofenceClockReading) {
        self.date = date
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

    /// Whether this mark overtakes every visit `other` does, which `other` then adds nothing to.
    /// Only on the same timeline: across a step, neither mark's dates order against the other's.
    func subsumes(_ other: GeofenceExitMark) -> Bool {
        abs(wallOffset - other.wallOffset) < 0.001
            && mappedUptime >= other.mappedUptime
            && processedUptime >= other.processedUptime
            && date >= other.date
    }
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
    func noteEnter(_ mark: GeofenceExitMark, geofenceId: String) {
        if let noted = enterMarks[geofenceId], noted.processedUptime >= mark.processedUptime,
           noted.mappedUptime >= mark.mappedUptime { return }
        enterMarks[geofenceId] = mark
    }

    /// Notes a native ENTER from the OS callback itself, before its routing task runs.
    func noteEnter(geofenceId: String, occurredAt: Date) {
        noteEnter(GeofenceExitMark(date: occurredAt, processedAt: readClock()), geofenceId: geofenceId)
    }

    /// Whether a native ENTER this process has seen is a later crossing than `visit`'s.
    func enterSuperseded(_ visit: GeofenceDwellVisit, geofenceId: String) -> Bool {
        enterMarks[geofenceId]?.supersedes(visit) ?? false
    }

    /// Whether an EXIT this process has seen for the fence ends `visit`.
    func exitOvertook(_ visit: GeofenceDwellVisit, geofenceId: String) -> Bool {
        exitMarks[geofenceId]?.contains { $0.overtakes(visit) } ?? false
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
