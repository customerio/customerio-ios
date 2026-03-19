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

/// Reads and writes pending push delivery metrics in the app group (file-backed JSON list).
/// The Notification Service Extension appends before starting the delivery HTTP request; the coordinator removes an entry after that request succeeds. The host app may also dequeue remaining rows on Data Pipeline startup.
public protocol PendingPushDeliveryStore: AutoMockable {
    /// App group identifier used with `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` (e.g. `group.com.example.app.cio`).
    var appGroupSuiteName: String { get }

    /// Appends a metric. When over capacity, drops the **oldest** entries. Returns `false` if the list could not be persisted.
    func append(_ metric: PendingPushDeliveryMetric) -> Bool

    /// All pending metrics, oldest first.
    func loadAll() -> [PendingPushDeliveryMetric]

    /// Removes one pending entry by id (e.g. after successful delivery in the NSE, or after the host app enqueues a flush). Returns `false` if the file could not be updated.
    func remove(id: UUID) -> Bool
}

// sourcery: InjectRegisterShared = "PendingPushDeliveryStore"
// sourcery: InjectSingleton
public final class CioAppGroupPendingPushDeliveryStore: PendingPushDeliveryStore {
    private let logger: Logger
    private let fileManager: FileManager
    private let maxEntries: Int
    private let lock = NSLock()
    /// When `nil` (bundle unresolved, App Group not in entitlements, etc.), read/write methods return early without locking; callers may always call `append`.
    private let metricsFileURL: URL?

    public let appGroupSuiteName: String

    init(
        deviceMetricsGrabber: DeviceMetricsGrabber,
        logger: Logger
    ) {
        self.logger = logger
        self.fileManager = .default
        self.maxEntries = PendingPushDeliveryMetricsConstants.maxEntries

        switch PendingPushDeliveryAppGroupStorage.resolve(
            processBundleIdentifier: deviceMetricsGrabber.appBundleId,
            fileManager: fileManager
        ) {
        case .ready(let suite, let url):
            self.appGroupSuiteName = suite
            self.metricsFileURL = url
        case .missingBundleIdentifier:
            self.appGroupSuiteName = ""
            self.metricsFileURL = nil
            logger.error("Pending push delivery store: missing bundle identifier; app group storage unavailable.")
        case .containerUnavailable(let suite):
            self.appGroupSuiteName = suite
            self.metricsFileURL = nil
            logger.error("Pending push delivery store: could not resolve app group container for suite \(suite).")
        }
    }

    public func append(_ metric: PendingPushDeliveryMetric) -> Bool {
        guard let fileURL = metricsFileURL else { return false }

        lock.lock()
        defer { lock.unlock() }

        var items = readItems(from: fileURL)
        items.append(metric)
        while items.count > maxEntries {
            items.removeFirst()
        }

        guard save(items, to: fileURL) else { return false }
        logger.debug("Pending push delivery store: appended metric id=\(metric.id) deliveryId=\(metric.deliveryId)")
        return true
    }

    public func loadAll() -> [PendingPushDeliveryMetric] {
        guard let fileURL = metricsFileURL else { return [] }

        lock.lock()
        defer { lock.unlock() }

        return readItems(from: fileURL)
    }

    public func remove(id: UUID) -> Bool {
        guard let fileURL = metricsFileURL else { return false }

        lock.lock()
        defer { lock.unlock() }

        let items = readItems(from: fileURL)
        let filtered = items.filter { $0.id != id }
        guard filtered.count != items.count else { return true }

        guard save(filtered, to: fileURL) else { return false }
        logger.debug("Pending push delivery store: removed metric id=\(id)")
        return true
    }

    private func readItems(from fileURL: URL) -> [PendingPushDeliveryMetric] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([PendingPushDeliveryMetric].self, from: data)
        } catch {
            logger.error("Pending push delivery store: failed to read or decode file — \(error.localizedDescription)")
            return []
        }
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
