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
    private let cache: Synchronized<BackgroundDeliveryContext>
    private let providerRef: Synchronized<WeakProviderRef>

    public convenience init() {
        self.init(fileManager: .default, directoryURL: nil)
    }

    /// Internal designated init exposed for tests via `@testable import CioInternalCommon`.
    init(fileManager: FileManager, directoryURL: URL?) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
        let url = Self.resolveFileURL(fileManager: fileManager, directoryURL: directoryURL)
        let initial = Self.loadFromDisk(fileManager: fileManager, fileURL: url) ?? BackgroundDeliveryContext()
        self.cache = Synchronized(initial)
        self.providerRef = Synchronized(WeakProviderRef())
    }

    // MARK: - Getters

    public var currentUserId: String? {
        cache.using { $0.userId }
    }

    public var currentApiHost: String? {
        cache.using { $0.apiHost }
    }

    /// Live key from the registered provider if present (foreground with DataPipeline init),
    /// otherwise the persisted key (cold-wake, or foreground with `allowBackgroundDelivery` off
    /// and no provider registered yet).
    public var currentCdpApiKey: String? {
        let live = providerRef.using { $0.provider?.cdpApiKey }
        if let live, !live.isEmpty { return live }
        return cache.using { $0.cdpApiKey }
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
        // effect — the file is what a cold-wake process reads.
        cache.mutating { value in
            mutator(&value)
            saveToDisk(value)
        }
    }

    private func saveToDisk(_ context: BackgroundDeliveryContext) {
        guard let url = fileURL(),
              let data = try? Self.makeEncoder().encode(context)
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
        } catch {
            return
        }
        // Post-write hardening (file protection class + backup exclusion) is best-effort —
        // bytes are already durable, so a failure here must not be reported as a save failure.
        try? fileManager.setAttributes(
            [.protectionKey: Self.protection],
            ofItemAtPath: url.path
        )
        setExcludedFromBackup(on: url)
    }

    private static func loadFromDisk(fileManager: FileManager, fileURL: URL?) -> BackgroundDeliveryContext? {
        guard let url = fileURL,
              fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? makeDecoder().decode(BackgroundDeliveryContext.self, from: data)
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
