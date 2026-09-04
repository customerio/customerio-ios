import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "GeofenceStorage"
// sourcery: InjectCustomShared
/// Thread-safe persistence for geofence state.
///
/// Implemented as an actor so all read-modify-write sequences are naturally atomic via
/// actor isolation — no locks, no `@unchecked Sendable`. State is persisted to a JSON
/// file with iOS Data Protection (`completeUntilFirstUserAuthentication`) so geofence
/// callbacks that fire while the app is killed can still read cooldowns after the first
/// user unlock. The file is excluded from backups (geofence cache is device-local context).
///
/// Each public method that mutates state performs the load → modify → save sequence
/// synchronously within the actor, so no `await` interleaves and updates can never be
/// lost to reentrancy.
actor GeofenceStorage {
    private static let defaultSubdirectory = "io.customer.sdk.geofence"
    private static let filename = "geofenceState.json"
    private static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    private let fileManager: FileManager
    private let directoryURL: URL?

    /// - Parameters:
    ///   - fileManager: File manager used for I/O. Defaults to `.default`.
    ///   - directoryURL: Directory for the state file. If `nil`, uses Application Support in the app container.
    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
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

    /// Atomically checks whether the cooldown window for `key` has expired and, if so,
    /// records the new timestamp. Returns `true` when the caller may proceed (no active
    /// cooldown), `false` when the event should be suppressed. The whole check-and-record
    /// runs inside the actor with no `await` between steps, so concurrent callers cannot
    /// both observe an expired window and both fire the event.
    func tryAcquireCooldown(key: String, now: Date, interval: TimeInterval) -> Bool {
        var state = loadFromDisk() ?? GeofenceState()
        var cooldowns = state.eventCooldowns ?? [:]
        if let last = cooldowns[key], now.timeIntervalSince(last) < interval {
            return false
        }
        cooldowns[key] = now
        state.eventCooldowns = cooldowns
        saveToDisk(state)
        return true
    }

    /// Atomically removes cooldown entries whose recorded timestamp is older than `interval`
    /// before `now`. Filtering happens inside the actor so a concurrent `tryAcquireCooldown`
    /// cannot have its fresh write deleted by a stale snapshot.
    func purgeExpiredCooldowns(now: Date, interval: TimeInterval) {
        var state = loadFromDisk() ?? GeofenceState()
        guard var cooldowns = state.eventCooldowns, !cooldowns.isEmpty else { return }
        let beforeCount = cooldowns.count
        cooldowns = cooldowns.filter { now.timeIntervalSince($0.value) < interval }
        if cooldowns.count == beforeCount { return }
        state.eventCooldowns = cooldowns
        saveToDisk(state)
    }

    /// Removes the cooldown entry for `key`, if present. Called when persist-first fails after the
    /// cooldown was already claimed, so the next transition of this type isn't suppressed against a
    /// metric that never reached the pending queue.
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

    /// Records that the CLMonitor path (re)registered a condition: stores the delivery filter, the
    /// circle geometry, and the dedup baseline. `initialState` is the device's ACTUAL state relative to
    /// the circle at registration (computed by the monitor from the current location), so a fresh
    /// baseline already matches reality — no spurious registration event, no missed first crossing.
    ///
    /// The baseline is **preserved** when the identifier is re-registered with unchanged geometry
    /// (stop-all + start-all runs on every sync), so CLMonitor re-evaluating the same state isn't
    /// delivered as a duplicate; it is **reseeded** to `initialState` for a brand-new identifier or a
    /// changed circle. The unchanged-vs-changed decision is keyed on the persisted `center`/`radius`
    /// (which survive stop-all) rather than CLMonitor's live record (which stop-all removes before the
    /// re-add, so it can never report "unchanged").
    ///
    /// `forceReseed` overrides that preservation. The caller sets it when the OS stopped monitoring
    /// the condition since the last registration: the device can cross while unmonitored, so the
    /// persisted state is no longer known to match reality and keeping it would suppress the next
    /// genuine crossing. Polygon belief reseeds with it, for the same reason.
    func recordMonitorRegistration(
        identifier: String,
        transitionTypes: Set<GeofenceTransition>,
        initialState: GeofenceTransition,
        center: LocationData,
        radius: Double,
        forceReseed: Bool = false,
        now: Date = Date()
    ) {
        var state = loadFromDisk() ?? GeofenceState()
        var records = state.monitorRegionRecords ?? [:]
        let existing = records[identifier]
        let unchangedGeometry = existing?.center == center && existing?.radius == radius
        let preserved = unchangedGeometry && !forceReseed
        records[identifier] = MonitorRegionRecord(
            lastState: preserved ? (existing?.lastState ?? initialState) : initialState,
            transitionTypes: transitionTypes,
            center: center,
            radius: radius,
            lastStateChangedAt: preserved ? existing?.lastStateChangedAt : now
        )
        state.monitorRegionRecords = records
        if forceReseed { state.dropPolygonBelief(for: identifier) }
        saveToDisk(state)
    }

    /// Records a state observed off `CLMonitor.events` and returns what to do with it. The whole
    /// compare-and-store runs inside the actor with no `await` between steps, so concurrent events
    /// cannot both observe a stale baseline and both deliver. The baseline advances on every state
    /// change — including transitions filtered from delivery — so an exit-only region still tracks
    /// that the device entered, and the following exit is recognized as a change.
    ///
    /// `onlyIfBaselinePredates` makes the write conditional on the baseline's age, atomically with
    /// the compare-and-store: when set, a baseline written after that instant suppresses the event.
    /// The heal passes its fix's timestamp — a genuine OS crossing landing while the heal waited in
    /// the queue (or within the fix's own age) must win over a decision made from an older position.
    func recordMonitorEvent(
        _ transition: GeofenceTransition,
        forIdentifier identifier: String,
        onlyIfBaselinePredates evidenceTimestamp: Date? = nil,
        now: Date = Date()
    ) -> GeofenceMonitorEventOutcome {
        var state = loadFromDisk() ?? GeofenceState()
        var records = state.monitorRegionRecords ?? [:]
        guard var record = records[identifier] else {
            // No registration record (condition predates this bookkeeping). Establish the baseline
            // without delivering — mirrors classic registration, which is silent about the initial state.
            records[identifier] = MonitorRegionRecord(lastState: transition, transitionTypes: [.enter, .exit], lastStateChangedAt: now)
            state.monitorRegionRecords = records
            saveToDisk(state)
            return .suppressedNoBaseline
        }
        if let evidenceTimestamp, let changedAt = record.lastStateChangedAt, changedAt > evidenceTimestamp {
            return .suppressedNewerBaseline
        }
        guard record.lastState != transition else { return .suppressedNoChange }
        record.lastState = transition
        record.lastStateChangedAt = now
        records[identifier] = record
        state.monitorRegionRecords = records
        saveToDisk(state)
        return record.transitionTypes.contains(transition) ? .deliver : .suppressedFilteredType
    }

    /// Snapshot of every per-condition monitor record — the adopt-time re-arm rebuilds conditions
    /// from the geometry and baselines stored here.
    func getMonitorRegionRecords() -> [String: MonitorRegionRecord] {
        loadFromDisk()?.monitorRegionRecords ?? [:]
    }

    /// Drops the baseline for a condition the OS stopped monitoring, so the next registration
    /// reseeds from the device's real position rather than carrying a state it may have left while
    /// unmonitored — an unchanged-geometry re-register would preserve that stale value.
    /// Drops both the OS-facing baseline and the polygon belief: the region is no longer monitored,
    /// so a belief kept across the gap would suppress the next real enter as no-change if the device
    /// left the polygon while nothing was watching.
    func clearMonitorRegionRecord(identifier: String) {
        var state = loadFromDisk() ?? GeofenceState()
        let hadRecord = state.monitorRegionRecords?.removeValue(forKey: identifier) != nil
        let hadBelief = state.polygonMembership?.removeValue(forKey: identifier) != nil
        guard hadRecord || hadBelief else { return }
        saveToDisk(state)
    }

    /// Clears the cooldown map, last-sync record, registration set, and monitor baselines but
    /// preserves the cached geofences and config. Called on sign-out: the workspace cache is shared
    /// across users, while cooldowns belong to the signed-out user and the last-sync anchor would
    /// otherwise let the freshness gate skip the first sync for the next signed-in user against stale
    /// state. `monitorRegionRecords` is dropped so the next session can't inherit a stale per-region
    /// baseline; re-registration reseeds it anyway.
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

    /// Returns the last successful server sync as an atomic `(timestamp, location)` pair.
    /// Returns `nil` if either half is missing — defensive against torn state that could
    /// arise from older clients or future schema changes.
    func getLastSync() -> LastSyncRecord? {
        guard let state = loadFromDisk(),
              let timestamp = state.lastServerSyncTimestamp,
              let location = state.lastServerSyncLocation
        else {
            return nil
        }
        return LastSyncRecord(timestamp: timestamp, location: location)
    }

    /// Records a successful server sync. Writes both timestamp and location in the same
    /// load-modify-save so a partial update cannot leave the two fields out of step.
    func recordSync(timestamp: Date, location: LocationData) {
        var state = loadFromDisk() ?? GeofenceState()
        state.lastServerSyncTimestamp = timestamp
        state.lastServerSyncLocation = location
        saveToDisk(state)
    }

    // MARK: - Last Registration

    /// Center of the most recent OS registration (the movement-trigger center). The sync
    /// decision measures distance from here to detect a stale ranking — the device moved
    /// beyond the trigger radius while the app was dead, so the registered nearest-set is
    /// no longer the closest geofences and needs a local re-rank.
    func getLastRegistrationCenter() -> LocationData? {
        loadFromDisk()?.movementTriggerCenter
    }

    /// Business geofence IDs registered with the OS at the last registration. Lets the sync
    /// decision spot a cache that holds regions while nothing is registered (e.g. regs lost
    /// on sign-out) and re-register instead of skipping.
    func getRegisteredBusinessIds() -> Set<String> {
        loadFromDisk()?.monitoredGeofenceIds ?? []
    }

    /// Records the registration anchor + business IDs in one load-modify-save. Updated on every
    /// registration, including a local re-rank, so the ranking-staleness reference follows the
    /// device. Distinct from `recordSync` (the API-fetch anchor), which a local re-rank leaves intact.
    func recordRegistration(center: LocationData, businessIds: Set<String>) {
        var state = loadFromDisk() ?? GeofenceState()
        state.movementTriggerCenter = center
        state.monitoredGeofenceIds = businessIds
        // Drop per-condition baselines for regions this registration no longer covers. A record
        // survives `stopMonitoring` on purpose, so an unchanged re-register keeps its baseline and
        // CLMonitor's re-evaluation stays silent — but a region *evicted* from the set is a
        // different case. It goes unmonitored, so no EXIT ever balances a `.enter` baseline, and a
        // later re-registration with the same circle keeps that stale value instead of the state
        // the device is actually in. The next genuine arrival then reads as no change and is
        // dropped. Retaining exactly the registered set bounds the records the same way
        // `monitoredGeofenceIds` is bounded, and clears anything a previous version stranded.
        if let records = state.monitorRegionRecords {
            let retained = businessIds.union([GeofenceConstants.movementTriggerIdentifier])
            state.monitorRegionRecords = records.filter { retained.contains($0.key) }
        }
        state.prunePolygonState(retaining: businessIds)
        saveToDisk(state)
    }

    // MARK: - Private (file persistence)

    // Internal (not private): reached by the `+PolygonMembership` extension in its own file.
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

/// Disposition of a state observed off `CLMonitor.events`, decided by
/// `GeofenceStorage.recordMonitorEvent(_:forIdentifier:)`.
enum GeofenceMonitorEventOutcome: Equatable, Sendable {
    /// Genuine state change of a registered transition type — deliver it.
    case deliver
    /// Same state as the baseline — a CLMonitor re-emission (relaunch/unlock/foreground), not a crossing.
    case suppressedNoChange
    /// Genuine state change, but the region wasn't registered for this transition type.
    case suppressedFilteredType
    /// First observation for a condition with no registration record — baseline established, nothing delivered.
    case suppressedNoBaseline
    /// The baseline was written after the caller's evidence (`onlyIfBaselinePredates`) — e.g. a
    /// heal whose fix predates an OS crossing that landed while the heal was queued.
    case suppressedNewerBaseline
}

// MARK: - DI

extension DIGraphShared {
    var customGeofenceStorage: GeofenceStorage {
        GeofenceStorage.shared
    }
}

extension GeofenceStorage {
    static let shared = GeofenceStorage()
}
