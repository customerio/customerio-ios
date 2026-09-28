import CioInternalCommon
import Foundation

/// What a read of the queue file found.
///
/// `unreadable` is not an empty list: treated as one, the next append replaces a queue that is
/// intact on disk. A read can fail while a write succeeds, since `Data.write(options: .atomic)`
/// renames a temp file into place and needs permission on the directory, not the target.
enum PendingGeofenceQueueRead: Equatable {
    /// The file was read. Rows that did not decode are skipped, counted, and logged by the store.
    case rows([PendingGeofenceMetric])
    /// The bytes could not be obtained. Nothing may be written over them.
    case unreadable
}

/// The outcome of a write. The two failures are reported differently: only one is a failed write.
enum PendingGeofenceQueueWrite: Equatable {
    case persisted
    /// Refused before writing, because the existing queue could not be read.
    case refusedUnreadable
    case writeFailed
}

/// File-backed queue of geofence transition events awaiting delivery.
///
/// Like `PendingPushDeliveryStore` but in the app's container: geofence callbacks run in the main
/// process, so no app group. Uses `completeUntilFirstUserAuthentication` and is excluded from
/// backups. Each method's load → modify → save runs without `await`.
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

    /// Appends in one read-modify-write so a transition's fan-out persists all-or-nothing. Rows
    /// whose `key` already exists are skipped; over capacity, the **oldest** are dropped. Refuses to
    /// write over an unreadable file.
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

    /// The pending queue, oldest first, or `unreadable`, which callers must not treat as empty.
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
        // Application Support could not be resolved. Unreadable, not empty, and logged: every
        // append and flush fails for the life of the process.
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
            // Not a row array: nothing to preserve, so it reads as empty and the next write reclaims it.
            logger.geofenceQueueUnreadable(reason: .notARowArray)
            return .rows([])
        }
        let decoded = rows.compactMap(\.metric)
        if decoded.count < rows.count {
            logger.geofenceQueueRowsDropped(count: rows.count - decoded.count, of: rows.count)
        }
        return .rows(decoded)
    }

    /// Decodes one row without failing the array, so a row the current schema can't read (schema
    /// evolution, e.g. non-optional `userId`/`transitionId`) doesn't discard the rest.
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
        // Best-effort: the bytes are already on disk, and reporting failure here would make the
        // caller retry and duplicate the row.
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
