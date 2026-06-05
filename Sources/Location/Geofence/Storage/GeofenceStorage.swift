import CioInternalCommon
import Foundation

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

    func clearEventCooldowns() {
        var state = loadFromDisk() ?? GeofenceState()
        state.eventCooldowns = nil
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
