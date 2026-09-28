import CioInternalCommon
import Foundation

/// `unreadable` is not empty: treated as empty, the next append replaces a queue intact on disk. A
/// read can fail while an atomic write (a rename into the directory) succeeds.
enum PendingGeofenceQueueRead: Equatable {
    case rows([PendingGeofenceMetric])
    case unreadable
}

enum PendingGeofenceQueueWrite: Equatable {
    case persisted
    case refusedUnreadable
    case writeFailed
}

/// In the app's container, not an app group: geofence callbacks run in the main process.
actor PendingGeofenceMetricStore {
    private static let defaultSubdirectory = "io.customer.sdk.geofence"
    private static let filename = "pending_geofence_metrics.json"
    private static let maxEntries = 100
    private static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    private let fileManager: FileManager
    private let directoryURL: URL?
    private let logger: Logger

    init(
        logger: Logger,
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) {
        self.logger = logger
        self.fileManager = fileManager
        self.directoryURL = directoryURL
    }

    /// One write, so a transition's fan-out persists all-or-nothing.
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

    /// Oldest first.
    func read() -> PendingGeofenceQueueRead {
        loadFromDisk()
    }

    func remove(key: String) -> Bool {
        guard case .rows(var items) = read() else { return false }
        let originalCount = items.count
        items.removeAll { $0.key == key }
        guard items.count != originalCount else { return false }
        return saveToDisk(items)
    }

    // MARK: - Private (file persistence)

    private func loadFromDisk() -> PendingGeofenceQueueRead {
        // Unreadable, not empty: every append and flush fails for the life of the process.
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

    /// Per row, so one the current schema can't read doesn't discard the rest.
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
        // Best-effort: the bytes are on disk, and a failure here would make the caller duplicate
        // the row.
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
