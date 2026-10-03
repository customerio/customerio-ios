import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "GeofenceStorage"
// sourcery: InjectCustomShared
/// Mutating methods run load → modify → save with no `await`, so updates can't be lost to
/// reentrancy. `completeUntilFirstUserAuthentication` so a relaunched killed app can read it.
actor GeofenceStorage {
    private static let defaultSubdirectory = "io.customer.sdk.geofence"
    private static let filename = "geofenceState.json"
    private static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    private let fileManager: FileManager
    private let directoryURL: URL?
    /// `lastStateChangedAt` is weighed against fix timestamps, so it must come from the same clock.
    private let dateUtil: DateUtil
    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        dateUtil: DateUtil = DIGraphShared.shared.dateUtil
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
        self.dateUtil = dateUtil
    }

    // MARK: - Monitor Region Records (CLMonitor path)

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
            lastStateObserved: preserved ? existing?.lastStateObserved : initialStateObserved
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

    /// `recordMonitorEvent`, also answering whether a delivered ENTER left an OBSERVED `.exit`.
    /// Only then is it a crossing since registration; out of an assumed one it may be `CLMonitor`
    /// correcting its `assuming:` for a device that never left. False for every other outcome.
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
    ) -> (outcome: GeofenceMonitorEventOutcome, entryObserved: Bool) {
        var state = loadFromDisk() ?? GeofenceState()
        var records = state.monitorRegionRecords ?? [:]
        guard var record = records[identifier] else {
            // Condition predates this bookkeeping. Silent, like classic registration's initial state.
            records[identifier] = MonitorRegionRecord(
                lastState: transition, transitionTypes: [.enter, .exit], lastStateChangedAt: now ?? dateUtil.now,
                lastEventDate: osEventDate, lastStateObserved: true
            )
            state.monitorRegionRecords = records
            saveToDisk(state)
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
            records[identifier] = record
            state.monitorRegionRecords = records
            saveToDisk(state)
            return (record.transitionTypes.contains(transition) ? .deliver : .suppressedFilteredType, false)
        }
        guard record.lastState != transition else {
            // Persist the date so a later copy is refused.
            if osEventDate != nil {
                records[identifier] = record
                state.monitorRegionRecords = records
                saveToDisk(state)
            }
            // Not an observation of an assumed state: `CLMonitor` may just be echoing `assuming:`.
            return (.suppressedNoChange, false)
        }
        let leftObservedState = record.lastStateObserved ?? false
        record.lastState = transition
        record.lastStateChangedAt = now ?? dateUtil.now
        record.lastStateObserved = true
        records[identifier] = record
        state.monitorRegionRecords = records
        let delivered = record.transitionTypes.contains(transition)
        let crossing = transition == .enter && leftObservedState
        if delivered, let reading, transition == .exit || crossing, let center = record.center, let radius = record.radius {
            Self.closeVisit(in: &state, identifier: identifier, registered: MonitoredCircle(center: center, radius: radius, maximumRadius: maximumRadius), endedBy: transition, mark: GeofenceExitMark(date: osEventDate ?? now ?? dateUtil.now, processedAt: reading))
        }
        saveToDisk(state)
        return (delivered ? .deliver : .suppressedFilteredType, crossing)
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

    /// Keeps the workspace's cached geofences and config. Clearing the last sync stops the freshness
    /// gate from skipping the next user's first sync.
    func clearUserScopedState() {
        var state = loadFromDisk() ?? GeofenceState()
        state.eventCooldowns = nil
        state.lastServerSyncTimestamp = nil
        state.lastServerSyncLocation = nil
        state.movementTriggerCenter = nil
        state.monitoredGeofenceIds = nil
        state.monitorRegionRecords = nil
        state.polygonMembership = nil
        state.dwellVisits = nil
        state.unconfiguredOsTransitions = nil
        saveToDisk(state)
    }

    // MARK: - Cached Geofences

    func getCachedGeofences() -> [Geofence] {
        loadFromDisk()?.cachedGeofences ?? []
    }

    func setCachedGeofences(_ geofences: [Geofence]) {
        var state = loadFromDisk() ?? GeofenceState()
        state.cachedGeofences = geofences
        state.dwellVisits = Self.dwellVisits(state.dwellVisits, retainedFor: geofences)
        saveToDisk(state)
    }

    // MARK: - Cached Config

    func getCachedConfig() -> GeofenceConfig? {
        loadFromDisk()?.cachedConfig
    }

    func setCachedConfig(_ config: GeofenceConfig) {
        var state = loadFromDisk() ?? GeofenceState()
        state.cachedConfig = config
        saveToDisk(state)
    }

    // MARK: - Last Sync

    func getLastSync() -> LastSyncRecord? {
        guard let state = loadFromDisk(),
              let timestamp = state.lastServerSyncTimestamp,
              let location = state.lastServerSyncLocation
        else {
            return nil
        }
        return LastSyncRecord(timestamp: timestamp, location: location)
    }

    func recordSync(timestamp: Date, location: LocationData) {
        var state = loadFromDisk() ?? GeofenceState()
        state.lastServerSyncTimestamp = timestamp
        state.lastServerSyncLocation = location
        saveToDisk(state)
    }

    // MARK: - Private (file persistence)

    func loadFromDisk() -> GeofenceState? {
        guard let url = stateFileURL() else { return nil }
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? Self.makeDecoder().decode(GeofenceState.self, from: data)
    }

    @discardableResult
    func saveToDisk(_ state: GeofenceState) -> Bool {
        guard let data = try? Self.makeEncoder().encode(state),
              let url = stateFileURL()
        else {
            return false
        }
        let directory = url.deletingLastPathComponent()
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: Self.protection]
        )
        setExcludedFromBackup(on: directory)
        do {
            try data.write(to: url, options: .atomic)
            try fileManager.setAttributes(
                [.protectionKey: Self.protection],
                ofItemAtPath: url.path
            )
            setExcludedFromBackup(on: url)
            return true
        } catch {
            return false
        }
    }

    private func setExcludedFromBackup(on url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private func stateFileURL() -> URL? {
        if let directory = directoryURL {
            return directory.appendingPathComponent(Self.filename)
        }
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport
            .appendingPathComponent(Self.defaultSubdirectory)
            .appendingPathComponent(Self.filename)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

/// The OS-date guards of `recordMonitorTransition`, outside the actor body to keep it under the
/// type-length cap; same file, so they stay private.
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

/// Outside the type body, which is at its cap; same file, so it shares `refusedByDate`.
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
