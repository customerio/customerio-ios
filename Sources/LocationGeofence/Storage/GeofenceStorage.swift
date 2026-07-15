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

    /// Records that the CLMonitor path (re)registered a condition: stores the delivery filter and
    /// sets the dedup baseline. `initialState` is the device's ACTUAL state relative to the circle at
    /// registration (computed by the monitor from the current location), so the baseline already
    /// matches reality — no spurious registration event, no missed first crossing. `resetBaseline:
    /// true` sets the baseline to `initialState` for a fresh circle (a new condition or changed
    /// geometry); `false` preserves an existing baseline (an unchanged-geometry re-registration —
    /// stop-all + start-all runs on every sync) so CLMonitor's re-evaluation of the same state isn't
    /// delivered as a duplicate. A brand-new identifier uses `initialState` either way.
    func recordMonitorRegistration(
        identifier: String,
        transitionTypes: Set<GeofenceTransition>,
        initialState: GeofenceTransition,
        resetBaseline: Bool
    ) {
        var state = loadFromDisk() ?? GeofenceState()
        var records = state.monitorRegionRecords ?? [:]
        let lastState = resetBaseline ? initialState : (records[identifier]?.lastState ?? initialState)
        records[identifier] = MonitorRegionRecord(lastState: lastState, transitionTypes: transitionTypes)
        state.monitorRegionRecords = records
        saveToDisk(state)
    }

    /// Records a state observed off `CLMonitor.events` and returns what to do with it. The whole
    /// compare-and-store runs inside the actor with no `await` between steps, so concurrent events
    /// cannot both observe a stale baseline and both deliver. The baseline advances on every state
    /// change — including transitions filtered from delivery — so an exit-only region still tracks
    /// that the device entered, and the following exit is recognized as a change.
    func recordMonitorEvent(_ transition: GeofenceTransition, forIdentifier identifier: String) -> GeofenceMonitorEventOutcome {
        var state = loadFromDisk() ?? GeofenceState()
        var records = state.monitorRegionRecords ?? [:]
        guard var record = records[identifier] else {
            // No registration record (condition predates this bookkeeping). Establish the baseline
            // without delivering — mirrors classic registration, which is silent about the initial state.
            records[identifier] = MonitorRegionRecord(lastState: transition, transitionTypes: [.enter, .exit])
            state.monitorRegionRecords = records
            saveToDisk(state)
            return .suppressedNoBaseline
        }
        guard record.lastState != transition else { return .suppressedNoChange }
        record.lastState = transition
        records[identifier] = record
        state.monitorRegionRecords = records
        saveToDisk(state)
        return record.transitionTypes.contains(transition) ? .deliver : .suppressedFilteredType
    }

    /// Clears the cooldown map and the last-sync record (timestamp + location) but
    /// preserves the cached geofences and config. Called on sign-out: the workspace cache
    /// is shared across users, while cooldowns belong to the signed-out user and the
    /// last-sync anchor would otherwise let the freshness gate skip the first sync for
    /// the next signed-in user against stale state.
    func clearUserScopedState() {
        var state = loadFromDisk() ?? GeofenceState()
        state.eventCooldowns = nil
        state.lastServerSyncTimestamp = nil
        state.lastServerSyncLocation = nil
        state.movementTriggerCenter = nil
        state.monitoredGeofenceIds = nil
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
        saveToDisk(state)
    }

    // MARK: - Private (file persistence)

    private func loadFromDisk() -> GeofenceState? {
        guard let url = stateFileURL() else { return nil }
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? Self.makeDecoder().decode(GeofenceState.self, from: data)
    }

    private func saveToDisk(_ state: GeofenceState) {
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
