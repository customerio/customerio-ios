import Foundation

// MARK: - App Group file location (suite + path in one place)

private enum PendingPushDeliveryAppGroupStorage {
    enum Resolution {
        case ready(suiteName: String, metricsFileURL: URL)
        case missingBundleIdentifier
        case containerUnavailable(suiteName: String)
    }

    /// Resolves the shared app group suite name and the JSON file URL under `…/io.customer/` in one step.
    static func resolve(
        processBundleIdentifier: String?,
        fileManager: FileManager
    ) -> Resolution {
        guard let suite = AppGroupIdentifier.identifier(forProcessBundleIdentifier: processBundleIdentifier) else {
            return .missingBundleIdentifier
        }
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: suite) else {
            return .containerUnavailable(suiteName: suite)
        }
        let directory = container.appendingPathComponent(PendingPushDeliveryMetricsConstants.storageSubdirectoryName, isDirectory: true)
        let url = directory.appendingPathComponent(PendingPushDeliveryMetricsConstants.storageFileName, isDirectory: false)
        return .ready(suiteName: suite, metricsFileURL: url)
    }
}

/// What a read of the pending-metrics file found.
///
/// `unreadable` is separate from an empty list because reporting it as "no rows" lets the next
/// append replace rows that are intact on disk. Reachable when a read fails but a write still
/// succeeds — an atomic write renames a temp file, so it needs permission on the directory.
public enum PendingPushDeliveryQueueRead: Equatable {
    /// Rows that did not decode are skipped and logged.
    case rows([PendingPushDeliveryMetric])
    /// The bytes could not be obtained. Nothing may be written over them.
    case unreadable
}

/// Reads and writes pending push delivery metrics in the app group (file-backed JSON list).
/// The Notification Service Extension appends before starting the delivery HTTP request; the coordinator removes an entry after that request succeeds. The host app may also dequeue remaining rows on Data Pipeline startup.
public protocol PendingPushDeliveryStore: AutoMockable {
    /// App group identifier used with `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` (e.g. `group.com.example.app.cio`).
    /// `nil` when the bundle identifier could not be resolved at initialization time and no explicit app group was provided.
    var appGroupSuiteName: String? { get }

    /// Appends a metric. When over capacity, drops the **oldest** entries. Returns `false` if the list could not be persisted.
    func append(_ metric: PendingPushDeliveryMetric) -> Bool

    /// All pending metrics, oldest first. Empty when the file could not be read — use ``read()``
    /// where that difference matters.
    func loadAll() -> [PendingPushDeliveryMetric]

    /// The pending queue, or `unreadable` when the bytes could not be obtained.
    func read() -> PendingPushDeliveryQueueRead

    /// Removes one pending entry by id (e.g. after successful delivery in the NSE).
    /// Returns `true` when the entry was found and removed, `false` when the entry was not found or the file could not be updated.
    func remove(id: UUID) -> Bool

    /// Removes all entries whose ids are in `ids` in a single coordinated read-modify-write.
    /// Prefer this over calling `remove(id:)` in a loop when flushing multiple metrics at once.
    /// Returns `true` when the file was updated successfully, `false` when none of the ids were present or on I/O failure.
    func removeAll(ids: Set<UUID>) -> Bool
}

public final class CioAppGroupPendingPushDeliveryStore: PendingPushDeliveryStore {
    private let logger: Logger
    private let fileManager: FileManager
    private let maxEntries: Int
    /// When `nil` (bundle unresolved, App Group not in entitlements, etc.), read/write methods return early; callers may always call `append`.
    private let metricsFileURL: URL?

    public let appGroupSuiteName: String?

    /// Designated initializer. When `appGroupId` is non-nil it is used directly; otherwise the identifier
    /// is inferred from `processBundleIdentifier` using the format `group.{bundleId}.cio`.
    /// - Parameter fileManager: Test seam; the app group container does not exist in a test host.
    init(
        appGroupId: String?,
        processBundleIdentifier: String?,
        logger: Logger,
        fileManager: FileManager = .default
    ) {
        self.logger = logger
        self.fileManager = fileManager
        self.maxEntries = PendingPushDeliveryMetricsConstants.maxEntries

        if let explicitId = appGroupId {
            self.appGroupSuiteName = explicitId
            guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: explicitId) else {
                self.metricsFileURL = nil
                logger.error("Pending push delivery store: could not resolve app group container for suite \(explicitId).")
                return
            }
            let directory = container.appendingPathComponent(PendingPushDeliveryMetricsConstants.storageSubdirectoryName, isDirectory: true)
            self.metricsFileURL = directory.appendingPathComponent(PendingPushDeliveryMetricsConstants.storageFileName, isDirectory: false)
        } else {
            switch PendingPushDeliveryAppGroupStorage.resolve(
                processBundleIdentifier: processBundleIdentifier,
                fileManager: fileManager
            ) {
            case .ready(let suite, let url):
                self.appGroupSuiteName = suite
                self.metricsFileURL = url
            case .missingBundleIdentifier:
                self.appGroupSuiteName = nil
                self.metricsFileURL = nil
                logger.error("Pending push delivery store: missing bundle identifier; app group storage unavailable.")
            case .containerUnavailable(let suite):
                self.appGroupSuiteName = suite
                self.metricsFileURL = nil
                logger.error("Pending push delivery store: could not resolve app group container for suite \(suite).")
            }
        }
    }

    public func append(_ metric: PendingPushDeliveryMetric) -> Bool {
        guard let fileURL = metricsFileURL else { return false }

        var coordError: NSError?
        var success = false

        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], writingItemAt: fileURL, options: .forReplacing, error: &coordError) { readURL, writeURL in
            // Never write over a file we could not read: treating it as empty replaces intact rows.
            guard case .rows(var items) = readItems(from: readURL) else { return }
            items.append(metric)
            if items.count > maxEntries {
                items = Array(items.suffix(maxEntries))
            }
            success = save(items, to: writeURL)
        }

        if let error = coordError {
            logger.error("Pending push delivery store: coordination error on append — \(error.localizedDescription)")
            return false
        }

        if success {
            logger.debug("Pending push delivery store: appended metric id=\(metric.id) deliveryId=\(metric.deliveryId)")
        }
        return success
    }

    public func loadAll() -> [PendingPushDeliveryMetric] {
        guard case .rows(let rows) = read() else { return [] }
        return rows
    }

    public func read() -> PendingPushDeliveryQueueRead {
        // No app group, so no write can land either. Unreadable, so no append is built on it.
        guard let fileURL = metricsFileURL else { return .unreadable }

        var coordError: NSError?
        var result: PendingPushDeliveryQueueRead = .unreadable

        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &coordError) { readURL in
            result = readItems(from: readURL)
        }

        if let error = coordError {
            logger.error("Pending push delivery store: coordination error on read — \(error.localizedDescription)")
            return .unreadable
        }
        return result
    }

    public func remove(id: UUID) -> Bool {
        guard let fileURL = metricsFileURL else { return false }

        var coordError: NSError?
        var wasRemoved = false

        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], writingItemAt: fileURL, options: .forReplacing, error: &coordError) { readURL, writeURL in
            guard case .rows(let items) = readItems(from: readURL) else { return }
            let filtered = items.filter { $0.id != id }
            guard filtered.count != items.count else {
                // Entry not found — nothing to write.
                return
            }
            wasRemoved = save(filtered, to: writeURL)
        }

        if let error = coordError {
            logger.error("Pending push delivery store: coordination error on remove — \(error.localizedDescription)")
            return false
        }

        if wasRemoved {
            logger.debug("Pending push delivery store: removed metric id=\(id)")
        }
        return wasRemoved
    }

    public func removeAll(ids: Set<UUID>) -> Bool {
        guard let fileURL = metricsFileURL else { return false }
        guard !ids.isEmpty else { return true }

        var coordError: NSError?
        var success = false

        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], writingItemAt: fileURL, options: .forReplacing, error: &coordError) { readURL, writeURL in
            guard case .rows(let items) = readItems(from: readURL) else { return }
            let filtered = items.filter { !ids.contains($0.id) }
            guard filtered.count != items.count else {
                // None of the ids were present — nothing to write, but the requested ids were not removed.
                return
            }
            success = save(filtered, to: writeURL)
        }

        if let error = coordError {
            logger.error("Pending push delivery store: coordination error on remove(ids:) — \(error.localizedDescription)")
            return false
        }

        if success {
            logger.debug("Pending push delivery store: removed \(ids.count) metric(s)")
        }
        return success
    }

    /// Decodes one row without failing the array. Every field is non-optional, so schema
    /// evolution alone can drop a row — and one `try?` around the array dropped the rest with it.
    private struct DecodedRow: Decodable {
        let metric: PendingPushDeliveryMetric?

        init(from decoder: Decoder) throws {
            self.metric = try? PendingPushDeliveryMetric(from: decoder)
        }
    }

    private func readItems(from fileURL: URL) -> PendingPushDeliveryQueueRead {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return .rows([])
        } catch {
            logger.error("Pending push delivery store: file could not be read, leaving it intact — \(error.localizedDescription)")
            return .unreadable
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let rows = try? decoder.decode([DecodedRow].self, from: data) else {
            // Read fine but not a row array: nothing to preserve, so the next write reclaims it.
            logger.error("Pending push delivery store: file is not a row array, starting fresh")
            return .rows([])
        }
        let decoded = rows.compactMap(\.metric)
        if decoded.count < rows.count {
            logger.error("Pending push delivery store: skipped \(rows.count - decoded.count) of \(rows.count) row(s) that did not decode")
        }
        return .rows(decoded)
    }

    private func save(_ items: [PendingPushDeliveryMetric], to fileURL: URL) -> Bool {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            logger.error("Pending push delivery store: failed to save — \(error.localizedDescription)")
            return false
        }
    }
}
