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
    /// Internal for the `+MonitorRegionRecords` extension.
    let dateUtil: DateUtil
    /// Test seam: runs inside `stageDwellReservation` before its load, so a test can interleave
    /// main-actor work with the reservation write. Nil in production.
    private var beforeReservationWrite: (@Sendable () async -> Void)?

    func setBeforeReservationWrite(_ hook: (@Sendable () async -> Void)?) {
        beforeReservationWrite = hook
    }

    func runBeforeReservationWrite() async {
        await beforeReservationWrite?()
    }

    /// Test seam, as `beforeReservationWrite`: runs inside `admitStagedDwellReservation` before its
    /// load.
    private var beforeAdmission: (@Sendable () async -> Void)?

    func setBeforeAdmission(_ hook: (@Sendable () async -> Void)?) {
        beforeAdmission = hook
    }

    func runBeforeAdmission() async {
        await beforeAdmission?()
    }

    /// Test seam, as `beforeReservationWrite`: runs inside `isPolygon(id:)` before its load.
    private var beforeShapeRead: (@Sendable () async -> Void)?

    func setBeforeShapeRead(_ hook: (@Sendable () async -> Void)?) {
        beforeShapeRead = hook
    }

    func runBeforeShapeRead() async {
        await beforeShapeRead?()
    }

    /// Test seam: makes `retractDwellReservation` report a failed persist without writing.
    private var retractionFails = false

    func setRetractionFails(_ fails: Bool) {
        retractionFails = fails
    }

    var retractionFailsForTesting: Bool { retractionFails }

    /// Test seam: makes `recordDwellProofLedger` report a failed persist without writing.
    private(set) var ledgerSaveFails = false

    func setLedgerSaveFails(_ fails: Bool) {
        ledgerSaveFails = fails
    }

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        dateUtil: DateUtil = DIGraphShared.shared.dateUtil
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
        self.dateUtil = dateUtil
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
        // User-scoped like the visits: another user's dwell is never delivered.
        state.orphanedDwells = nil
        state.unconfiguredOsTransitions = nil
        saveToDisk(state)
    }

    // MARK: - Cached Geofences

    func getCachedGeofences() -> [Geofence] {
        loadFromDisk()?.cachedGeofences ?? []
    }

    /// Takes only regions decoded by the current model from a server response: it marks the
    /// catalog current, which ends the one-time refetch of a catalog cached before dwell support.
    func setCachedGeofences(_ geofences: [Geofence]) {
        var state = loadFromDisk() ?? GeofenceState()
        state.cachedGeofences = geofences
        state.catalogVersion = GeofenceState.currentCatalogVersion
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

    /// Whether no state has been written at all, as opposed to a state file that cannot be read
    /// now (e.g. Data Protection before first unlock, or an undecodable file).
    func stateIsAbsent() -> Bool {
        guard let url = stateFileURL() else { return false }
        return !fileManager.fileExists(atPath: url.path)
    }

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
