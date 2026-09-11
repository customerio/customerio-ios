import CioInternalCommon
import Foundation

/// What a read of the queue file found.
///
/// `unreadable` is a case of its own rather than an empty list because the two demand opposite
/// handling: reported as "no rows", it lets the next append replace a queue that is intact on
/// disk. The state that does the damage is a read that fails while a write would still succeed —
/// measured, since `Data.write(options: .atomic)` renames a temp file into place and needs
/// permission on the directory, not on the target. Data Protection is the suspected way the
/// device reaches it, but that chain is unverified: if the target's protection class also blocks
/// the write, the old code failed safe by accident.
enum PendingGeofenceQueueRead: Equatable {
    /// The file was read. Rows that did not decode are skipped, counted, and logged by the store.
    case rows([PendingGeofenceMetric])
    /// The bytes could not be obtained. Nothing may be written over them.
    case unreadable
}

/// The outcome of a write, kept apart because the caller reports them differently: nothing was
/// written in either case, but only one of them is a write that failed.
enum PendingGeofenceQueueWrite: Equatable {
    case persisted
    /// Refused before writing, because the existing queue could not be read.
    case refusedUnreadable
    case writeFailed
}

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
    private let logger: Logger

    /// - Parameters:
    ///   - logger: Reports rows skipped on read; the store is the only place that knows the count.
    ///   - fileManager: File manager used for I/O. Defaults to `.default`.
    ///   - directoryURL: Directory for the queue file. If `nil`, uses Application Support in the app container.
    init(
        logger: Logger,
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) {
        self.logger = logger
        self.fileManager = fileManager
        self.directoryURL = directoryURL
    }

    /// Appends metrics in one read-modify-write so a transition's fan-out persists atomically —
    /// a crash can't save some rows and lose the rest. Rows whose `key` already exists (on disk
    /// or earlier in `metrics`) are a no-op. When over capacity, drops the **oldest** first.
    ///
    /// Refuses to write over an unreadable file: the append would otherwise replace a queue whose
    /// rows are intact on disk and merely out of reach.
    func append(_ metrics: [PendingGeofenceMetric]) -> PendingGeofenceQueueWrite {
        guard !metrics.isEmpty else { return .persisted }
        guard case .rows(var items) = read() else { return .refusedUnreadable }
        var keys = Set(items.map(\.key))
        for metric in metrics where keys.insert(metric.key).inserted {
            items.append(metric)
        }
        if items.count > Self.maxEntries {
            items = Array(items.suffix(Self.maxEntries))
        }
        return saveToDisk(items) ? .persisted : .writeFailed
    }

    /// The pending queue, oldest first, or `unreadable`. Callers must handle the two apart —
    /// a caller that treats `unreadable` as an empty queue reintroduces the bug this exists for.
    func read() -> PendingGeofenceQueueRead {
        loadFromDisk()
    }

    /// Removes one pending entry by key. Returns `true` when the entry was found and removed,
    /// `false` when it was absent, the file was unreadable, or the write failed.
    func remove(key: String) -> Bool {
        guard case .rows(var items) = read() else { return false }
        let originalCount = items.count
        items.removeAll { $0.key == key }
        guard items.count != originalCount else { return false }
        return saveToDisk(items)
    }

    // MARK: - Private (file persistence)

    private func loadFromDisk() -> PendingGeofenceQueueRead {
        // A nil URL means Application Support could not be resolved, so no write ever landed.
        // Reported as unreadable rather than empty because `saveToDisk` cannot succeed either —
        // and logged, because every append and every flush then fails for the life of the process.
        guard let url = fileURL() else {
            logger.geofenceQueueUnreadable(reason: .noFileLocation)
            return .unreadable
        }
        guard fileManager.fileExists(atPath: url.path) else { return .rows([]) }
        guard let data = try? Data(contentsOf: url) else {
            logger.geofenceQueueUnreadable(reason: .readFailed)
            return .unreadable
        }
        guard let rows = try? Self.makeDecoder().decode([DecodedRow].self, from: data) else {
            // The bytes came back but are not a row array. Unlike a read failure there is nothing
            // to preserve, so the queue reads as empty and the next write reclaims the file.
            logger.geofenceQueueUnreadable(reason: .notARowArray)
            return .rows([])
        }
        let decoded = rows.compactMap(\.metric)
        if decoded.count < rows.count {
            logger.geofenceQueueRowsDropped(count: rows.count - decoded.count, of: rows.count)
        }
        return .rows(decoded)
    }

    /// Decodes one row without failing the array. A row the current schema cannot read is skipped
    /// and counted; a single `try?` around the whole array discarded every other row with it, and
    /// `userId`/`transitionId` are non-optional, so schema evolution alone can trigger it.
    private struct DecodedRow: Decodable {
        let metric: PendingGeofenceMetric?

        init(from decoder: Decoder) throws {
            self.metric = try? PendingGeofenceMetric(from: decoder)
        }
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
