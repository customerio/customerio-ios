import CioInternalCommon
import Foundation

/// File-backed queue of geofence transition events awaiting direct-HTTP delivery.
///
/// Same persistence shape as `PendingPushDeliveryStore` but in the app's container
/// (geofence callbacks run in the main process — no app group needed). File uses
/// `completeUntilFirstUserAuthentication` Data Protection and is excluded from backups.
///
/// Actor-isolated: every method's load → modify → save runs without `await`, so
/// concurrent callers can't observe a half-applied state.
///
/// Leftover rows are flushed on next module init. RN/Flutter wrappers may defer that
/// flush indefinitely if the SDK isn't re-initialized.
actor PendingGeofenceMetricStore {
    private static let defaultSubdirectory = "io.customer.sdk.geofence"
    private static let filename = "pending_geofence_metrics.json"
    private static let maxEntries = 100
    private static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    private let fileManager: FileManager
    private let directoryURL: URL?

    /// - Parameters:
    ///   - fileManager: File manager used for I/O. Defaults to `.default`.
    ///   - directoryURL: Directory for the queue file. If `nil`, uses Application Support in the app container.
    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
    }

    /// Appends a metric. When over capacity, drops the **oldest** entries first.
    /// A row with the same `key` is a no-op.
    /// Returns `false` if the file could not be persisted.
    func append(_ metric: PendingGeofenceMetric) -> Bool {
        var items = loadFromDisk()
        if items.contains(where: { $0.key == metric.key }) {
            // Already persisted — treat as success so the caller doesn't retry.
            return true
        }
        items.append(metric)
        if items.count > Self.maxEntries {
            items = Array(items.suffix(Self.maxEntries))
        }
        return saveToDisk(items)
    }

    /// All pending metrics, oldest first.
    func loadAll() -> [PendingGeofenceMetric] {
        loadFromDisk()
    }

    /// Removes one pending entry by key. Returns `true` when the entry was found and removed.
    func remove(key: String) -> Bool {
        var items = loadFromDisk()
        let originalCount = items.count
        items.removeAll { $0.key == key }
        guard items.count != originalCount else { return false }
        return saveToDisk(items)
    }

    /// Removes entries whose keys are in `keys` in one read-modify-write.
    /// Returns `true` when the file was updated, `false` when none of the keys were present.
    func removeAll(keys: Set<String>) -> Bool {
        guard !keys.isEmpty else { return true }
        var items = loadFromDisk()
        let originalCount = items.count
        items.removeAll { keys.contains($0.key) }
        guard items.count != originalCount else { return false }
        return saveToDisk(items)
    }

    /// Wipes the queue. Used on sign-out to avoid sending one user's queued events with the next user's identifier.
    func clearAll() {
        _ = saveToDisk([])
    }

    // MARK: - Private (file persistence)

    private func loadFromDisk() -> [PendingGeofenceMetric] {
        guard let url = fileURL(),
              fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else {
            return []
        }
        // Corrupted or unreadable JSON returns empty so the next write overwrites it.
        return (try? Self.makeDecoder().decode([PendingGeofenceMetric].self, from: data)) ?? []
    }

    private func saveToDisk(_ items: [PendingGeofenceMetric]) -> Bool {
        guard let url = fileURL(),
              let data = try? Self.makeEncoder().encode(items)
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
        } catch {
            return false
        }
        // Post-write hardening (file protection class + backup exclusion) is best-effort.
        // The bytes are already durable on disk, so a failure here must not be reported as
        // a save failure — the caller would otherwise treat the row as un-persisted and
        // retry, which could lead to duplicate entries.
        try? fileManager.setAttributes(
            [.protectionKey: Self.protection],
            ofItemAtPath: url.path
        )
        setExcludedFromBackup(on: url)
        return true
    }

    private func setExcludedFromBackup(on url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private func fileURL() -> URL? {
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
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
