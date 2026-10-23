import Foundation

/// State needed to call the CDP API from a context where the full SDK isn't initialized
/// (e.g. cold-wake background callbacks like geofence transitions): the identified `userId`,
/// the resolved CDP `apiHost`, and the workspace `cdpApiKey`.
///
/// Captured during a foreground session and read back at cold-wake. Producer is
/// `DataPipelineImplementation` (single owner); consumers are background-delivery features
/// like geofence today, potentially BGTaskScheduler tasks and Live Activities later.
public struct BackgroundDeliveryContext: Codable, Equatable, Sendable {
    public var userId: String?
    public var apiHost: String?
    public var cdpApiKey: String?

    public init(userId: String? = nil, apiHost: String? = nil, cdpApiKey: String? = nil) {
        self.userId = userId
        self.apiHost = apiHost
        self.cdpApiKey = cdpApiKey
    }
}

/// Supplies the live `cdpApiKey` so foreground real-time delivery works without forcing
/// customers to opt into on-disk persistence. `DataPipelineImplementation` registers itself
/// at init; on cold-wake (no DataPipeline in this process) the provider is nil and callers
/// fall back to the persisted value in `BackgroundDeliveryContextStore`.
public protocol BackgroundDeliveryCdpApiKeyProvider: AnyObject {
    var cdpApiKey: String? { get }
}

private final class WeakProviderRef {
    weak var provider: BackgroundDeliveryCdpApiKeyProvider?
}

/// The context with its identity version and lineage. The version counts every real change of user
/// in this lineage; the lineage is a random token the record is given when it is created, so a
/// count restarted by a lost or unreadable record never repeats an earlier lineage's. Persisted
/// together, in one write, so a change of user and its version are never apart.
private struct StoredContext {
    var context: BackgroundDeliveryContext
    var userVersion: UInt64
    var userLineage: String

    static func fresh(_ context: BackgroundDeliveryContext = BackgroundDeliveryContext(), version: UInt64 = 0) -> StoredContext {
        StoredContext(context: context, userVersion: version, userLineage: UUID().uuidString)
    }
}

/// The file format: the public context's keys, plus `userVersion` and `userLineage`. A build that
/// predates them reads the same file as `BackgroundDeliveryContext` and ignores the extra keys; a
/// file it wrote has neither, read as version 0 in a new lineage.
private struct PersistedContext: Codable {
    var userId: String?
    var apiHost: String?
    var cdpApiKey: String?
    var userVersion: UInt64?
    var userLineage: String?
}

/// What reading the file found.
private enum LoadedContext {
    /// Read and decoded, with its lineage.
    case current(StoredContext)
    /// Read and decoded, but written before the lineage: kept, in a new lineage.
    case legacy(StoredContext)
    /// No file, or one that does not decode: a new record in a new lineage.
    case replaceable
    /// A file that could not be read — locked, or an I/O error. A new lineage, but the file is
    /// left alone: its bytes may be good once readable.
    case unreadable
}

// sourcery: InjectRegisterShared = "BackgroundDeliveryContextStore"
// sourcery: InjectCustomShared
/// File-backed single store for `BackgroundDeliveryContext`. JSON file in Application Support
/// with iOS Data Protection (`completeUntilFirstUserAuthentication`), excluded from backups —
/// encrypted at rest, decrypted after first user unlock, not reachable via iCloud restore.
///
/// Concurrency: in-memory cache wrapped in `Synchronized`. Synchronous getters/setters preserve
/// the cold-wake delivery hot path; writes are rare (DataPipeline init, identify/reset paths) so
/// actor isolation would force async cascade for no concurrency benefit.
public final class BackgroundDeliveryContextStore: @unchecked Sendable {
    private static let defaultSubdirectory = "io.customer.sdk.background"
    private static let filename = "delivery_context.json"
    private static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    private let fileManager: FileManager
    private let directoryURL: URL?
    /// Writes the file. A seam for tests to fail a write; production writes atomically.
    private let writeData: (Data, URL) throws -> Void
    private let cache: Synchronized<StoredContext>
    private let providerRef: Synchronized<WeakProviderRef>
    private var snapshotObserver: NSObjectProtocol?

    public convenience init() {
        self.init(fileManager: .default, directoryURL: nil)
    }

    /// Internal designated init exposed for tests via `@testable import CioInternalCommon`.
    init(
        fileManager: FileManager,
        directoryURL: URL?,
        writeData: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
        self.writeData = writeData
        let url = Self.resolveFileURL(fileManager: fileManager, directoryURL: directoryURL)
        let initial: StoredContext
        let persistLineage: Bool
        switch Self.loadFromDisk(fileManager: fileManager, fileURL: url) {
        case .current(let stored): (initial, persistLineage) = (stored, false)
        case .legacy(let stored): (initial, persistLineage) = (stored, true)
        case .replaceable: (initial, persistLineage) = (.fresh(), true)
        case .unreadable: (initial, persistLineage) = (.fresh(), false)
        }
        self.cache = Synchronized(initial)
        self.providerRef = Synchronized(WeakProviderRef())
        // A new lineage is written at once, so the next process on this file reads the same one.
        // If the write fails, this lineage stays this process's alone, and matches nothing later.
        if persistLineage {
            cache.using { _ = saveToDisk($0) }
        }
        // Answers `userSnapshotRequest` for this store only, outside its lock.
        self.snapshotObserver = NotificationCenter.default.addObserver(
            forName: Self.userSnapshotRequest, object: self, queue: nil
        ) { [weak self] notification in
            guard let self, let reply = notification.userInfo?[Self.replyKey] as? (String?, UInt64, String) -> Void else { return }
            let snapshot = cache.using { ($0.context.userId, $0.userVersion, $0.userLineage) }
            reply(snapshot.0, snapshot.1, snapshot.2)
        }
    }

    deinit {
        if let snapshotObserver { NotificationCenter.default.removeObserver(snapshotObserver) }
    }

    // MARK: - Getters

    public var currentUserId: String? {
        cache.using { $0.context.userId }
    }

    public var currentApiHost: String? {
        cache.using { $0.context.apiHost }
    }

    /// Live key from the registered provider if present (foreground with DataPipeline init),
    /// otherwise the persisted key (cold-wake, or foreground with `allowBackgroundDelivery` off
    /// and no provider registered yet).
    public var currentCdpApiKey: String? {
        let live = providerRef.using { $0.provider?.cdpApiKey }
        if let live, !live.isEmpty { return live }
        return cache.using { $0.context.cdpApiKey }
    }

    /// Whether a registered provider is currently supplying a key — i.e. DataPipeline has
    /// initialized in this process. Lets callers distinguish "SDK is up, hand work to it" from
    /// "cold-wake, deliver directly off the persisted context".
    public var hasLiveCdpApiKeyProvider: Bool {
        providerRef.using { $0.provider?.cdpApiKey?.isEmpty == false }
    }

    /// Registers a live source for `cdpApiKey`. Held weakly so the provider's lifecycle
    /// drives availability — when the provider is deallocated (or never registered, as on
    /// cold-wake), `currentCdpApiKey` falls back to the persisted value.
    public func setCdpApiKeyProvider(_ provider: BackgroundDeliveryCdpApiKeyProvider?) {
        providerRef.mutating { $0.provider = provider }
    }

    // MARK: - Setters

    /// Empty strings are treated as a clear, not stored — guards against persisting `""`
    /// as if it were a valid identifier.
    public func setUserId(_ userId: String?) {
        updateAndSave { $0.userId = normalized(userId) }
    }

    public func setApiHost(_ apiHost: String?) {
        updateAndSave { $0.apiHost = normalized(apiHost) }
    }

    public func setCdpApiKey(_ key: String?) {
        updateAndSave { $0.cdpApiKey = normalized(key) }
    }

    public func clearUserId() {
        setUserId(nil)
    }

    /// Posted on `NotificationCenter.default`, with this store as the object, when the stored user
    /// actually changes — not for a repeat, nor an empty string where none was stored. Posted
    /// synchronously inside the update's critical section, after the change and its version were
    /// written to disk, so observers see changes in the order they were made. An observer therefore
    /// runs under the store's lock and must not call back into the store, nor post
    /// `userSnapshotRequest`. `userInfo[userIdKey]` is the new user, absent when cleared;
    /// `userInfo[userVersionKey]` is the identity version the change produced, and
    /// `userInfo[userLineageKey]` the lineage it counts in.
    ///
    /// Internal, not public: other SDK modules match names and keys by their string values.
    static let userIdDidChangeNotification = Notification.Name("io.customer.sdk.BackgroundDeliveryContextStore.userIdDidChange")
    static let userIdKey = "userId"
    static let userVersionKey = "userVersion"
    static let userLineageKey = "userLineage"

    /// Post with this store as the object and `userInfo[replyKey]` a `(String?, UInt64, String) ->
    /// Void`: the store calls it synchronously, outside its lock, with the user, identity version
    /// and lineage read together. Within a lineage the version only grows, by one per real change
    /// of user, and survives the process; a lost or unreadable record starts a new lineage.
    static let userSnapshotRequest = Notification.Name("io.customer.sdk.BackgroundDeliveryContextStore.userSnapshotRequest")
    static let replyKey = "reply"

    /// Wipes all delivery context. Used when callers want to ensure no stale config
    /// remains on disk (e.g. opting out of background direct delivery).
    public func reset() {
        updateAndSave { $0 = BackgroundDeliveryContext() }
    }

    // MARK: - Private

    private func normalized(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func updateAndSave(_ mutator: (inout BackgroundDeliveryContext) -> Void) {
        // Disk write under the lock so concurrent writers can't reorder their on-disk
        // effect — the file is what a cold-wake process reads. The user-change notification is
        // posted under it too, for the same reason.
        cache.mutating { stored in
            let previousUserId = stored.context.userId
            mutator(&stored.context)
            let userChanged = stored.context.userId != previousUserId
            if userChanged { stored.userVersion += 1 }
            if !saveToDisk(stored), userChanged {
                // The file still names the previous user at the previous version. Left there, the
                // next process would take it as current; removed, it starts a new lineage. If the
                // removal fails too, nothing can be persisted: this process still holds the change.
                removeRecord()
            }
            guard userChanged else { return }
            var userInfo: [String: Any] = [Self.userVersionKey: stored.userVersion, Self.userLineageKey: stored.userLineage]
            userInfo[Self.userIdKey] = stored.context.userId
            NotificationCenter.default.post(name: Self.userIdDidChangeNotification, object: self, userInfo: userInfo)
        }
    }

    /// Whether the record reached the file.
    @discardableResult
    private func saveToDisk(_ stored: StoredContext) -> Bool {
        let persisted = PersistedContext(
            userId: stored.context.userId, apiHost: stored.context.apiHost,
            cdpApiKey: stored.context.cdpApiKey, userVersion: stored.userVersion,
            userLineage: stored.userLineage
        )
        guard let url = fileURL(),
              let data = try? Self.makeEncoder().encode(persisted)
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
            try writeData(data, url)
        } catch {
            return false
        }
        // Post-write hardening (file protection class + backup exclusion) is best-effort —
        // bytes are already durable, so a failure here must not be reported as a save failure.
        try? fileManager.setAttributes(
            [.protectionKey: Self.protection],
            ofItemAtPath: url.path
        )
        setExcludedFromBackup(on: url)
        return true
    }

    private func removeRecord() {
        guard let url = fileURL() else { return }
        try? fileManager.removeItem(at: url)
    }

    private static func loadFromDisk(fileManager: FileManager, fileURL: URL?) -> LoadedContext {
        guard let url = fileURL, fileManager.fileExists(atPath: url.path) else { return .replaceable }
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        guard let persisted = try? makeDecoder().decode(PersistedContext.self, from: data) else { return .replaceable }
        let context = BackgroundDeliveryContext(
            userId: persisted.userId, apiHost: persisted.apiHost, cdpApiKey: persisted.cdpApiKey
        )
        guard let lineage = persisted.userLineage, !lineage.isEmpty else {
            return .legacy(.fresh(context, version: persisted.userVersion ?? 0))
        }
        return .current(StoredContext(context: context, userVersion: persisted.userVersion ?? 0, userLineage: lineage))
    }

    private func setExcludedFromBackup(on url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private func fileURL() -> URL? {
        Self.resolveFileURL(fileManager: fileManager, directoryURL: directoryURL)
    }

    private static func resolveFileURL(fileManager: FileManager, directoryURL: URL?) -> URL? {
        if let directory = directoryURL {
            return directory.appendingPathComponent(filename)
        }
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport
            .appendingPathComponent(defaultSubdirectory)
            .appendingPathComponent(filename)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}

// Extension to provide custom BackgroundDeliveryContextStore initialization in DIGraphShared.
// Uses a singleton so identity-event writes and cold-wake reads share one cached instance.
extension DIGraphShared {
    var customBackgroundDeliveryContextStore: BackgroundDeliveryContextStore {
        BackgroundDeliveryContextStore.shared
    }
}

extension BackgroundDeliveryContextStore {
    static let shared = BackgroundDeliveryContextStore()
}
