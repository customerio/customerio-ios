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

    // MARK: - Event Cooldowns

    func getEventCooldowns() -> [String: Date] {
        loadFromDisk()?.eventCooldowns ?? [:]
    }

    func recordEventCooldown(key: String, timestamp: Date) {
        var state = loadFromDisk() ?? GeofenceState()
        var cooldowns = state.eventCooldowns ?? [:]
        cooldowns[key] = timestamp
        state.eventCooldowns = cooldowns
        saveToDisk(state)
    }

    /// Checks and records in one step, so concurrent callers can't both fire.
    /// - Returns: `nil` when acquired, otherwise the seconds still left on the cooldown.
    func tryAcquireCooldown(key: String, now: Date, interval: TimeInterval) -> TimeInterval? {
        var state = loadFromDisk() ?? GeofenceState()
        var cooldowns = state.eventCooldowns ?? [:]
        if let last = cooldowns[key] {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < interval { return interval - elapsed }
        }
        cooldowns[key] = now
        state.eventCooldowns = cooldowns
        saveToDisk(state)
        return nil
    }

    /// Filtered inside the actor so a concurrent `tryAcquireCooldown` write can't be lost.
    func purgeExpiredCooldowns(now: Date, interval: TimeInterval) {
        var state = loadFromDisk() ?? GeofenceState()
        guard var cooldowns = state.eventCooldowns, !cooldowns.isEmpty else { return }
        let beforeCount = cooldowns.count
        cooldowns = cooldowns.filter { now.timeIntervalSince($0.value) < interval }
        if cooldowns.count == beforeCount { return }
        state.eventCooldowns = cooldowns
        saveToDisk(state)
    }

    /// For when persisting fails after the claim, so the next transition isn't suppressed.
    func releaseCooldown(key: String) {
        var state = loadFromDisk() ?? GeofenceState()
        guard var cooldowns = state.eventCooldowns, cooldowns.removeValue(forKey: key) != nil else { return }
        state.eventCooldowns = cooldowns
        saveToDisk(state)
    }

    func clearEventCooldowns() {
        var state = loadFromDisk() ?? GeofenceState()
        state.eventCooldowns = nil
        saveToDisk(state)
    }

    // MARK: - Monitor Region Records (CLMonitor path)

    /// The baseline is preserved on a re-register with unchanged geometry, so a CLMonitor
    /// re-evaluation isn't a duplicate. `forceReseed` after the OS stopped monitoring: the device may
    /// have crossed meanwhile.
    func recordMonitorRegistration(
        identifier: String,
        transitionTypes: Set<GeofenceTransition>,
        initialState: GeofenceTransition,
        center: LocationData,
        radius: Double,
        forceReseed: Bool = false,
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
            lastEventDate: (preserved || identifier == GeofenceConstants.movementTriggerIdentifier) ? existing?.lastEventDate : nil
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
        now: Date? = nil
    ) -> GeofenceMonitorEventOutcome {
        var state = loadFromDisk() ?? GeofenceState()
        var records = state.monitorRegionRecords ?? [:]
        guard var record = records[identifier] else {
            // Condition predates this bookkeeping. Silent, like classic registration's initial state.
            records[identifier] = MonitorRegionRecord(
                lastState: transition, transitionTypes: [.enter, .exit], lastStateChangedAt: now ?? dateUtil.now, lastEventDate: osEventDate
            )
            state.monitorRegionRecords = records
            saveToDisk(state)
            return .suppressedNoBaseline
        }
        // A trigger exit can arrive just after a re-plant, carrying the old circle's date. Only the
        // untouched re-plant baseline is exempt; later evidence keeps the ordering guard.
        let delayedMovementExit: Bool
        if identifier == GeofenceConstants.movementTriggerIdentifier, transition == .exit,
           let osEventDate, let registeredAt = record.registeredAt,
           let changedAt = record.lastStateChangedAt {
            delayedMovementExit = osEventDate < registeredAt && changedAt == registeredAt
        } else {
            delayedMovementExit = false
        }
        if let osEventDate {
            if !delayedMovementExit,
               let registeredAt = record.registeredAt, osEventDate < registeredAt { return .suppressedPredatesRegistration }
            if let lastEventDate = record.lastEventDate, osEventDate <= lastEventDate { return .suppressedRedelivery }
            record.lastEventDate = osEventDate
        }
        if !delayedMovementExit,
           let evidenceTimestamp, let changedAt = record.lastStateChangedAt, changedAt > evidenceTimestamp {
            return .suppressedNewerBaseline
        }
        if delayedMovementExit {
            // Keep the new circle's seeded state, or its next real exit would look unchanged.
            records[identifier] = record
            state.monitorRegionRecords = records
            saveToDisk(state)
            return record.transitionTypes.contains(transition) ? .deliver : .suppressedFilteredType
        }
        guard record.lastState != transition else {
            // Persist the date so a later copy is refused.
            if osEventDate != nil {
                records[identifier] = record
                state.monitorRegionRecords = records
                saveToDisk(state)
            }
            return .suppressedNoChange
        }
        record.lastState = transition
        record.lastStateChangedAt = now ?? dateUtil.now
        records[identifier] = record
        state.monitorRegionRecords = records
        saveToDisk(state)
        return record.transitionTypes.contains(transition) ? .deliver : .suppressedFilteredType
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
        saveToDisk(state)
    }

    // MARK: - Cached Geofences

    func getCachedGeofences() -> [Geofence] {
        loadFromDisk()?.cachedGeofences ?? []
    }

    func setCachedGeofences(_ geofences: [Geofence]) {
        var state = loadFromDisk() ?? GeofenceState()
        state.cachedGeofences = geofences
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

    func saveToDisk(_ state: GeofenceState) {
        guard let data = try? Self.makeEncoder().encode(state),
              let url = stateFileURL()
        else {
            return
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
        } catch {
            // Persistence is best-effort.
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
