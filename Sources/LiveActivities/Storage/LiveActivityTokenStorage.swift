import Foundation

/// Persists push-to-start token state for Live Activities.
///
/// One token is stored per activity type. The module uses this to skip re-registering
/// a token that has already been sent to the backend.
protocol LiveActivityTokenStorage {
    func getPushToStartToken(activityType: String) -> String?
    func setPushToStartToken(activityType: String, tokenHex: String)
    func clearAll()
}

/// File-based implementation of `LiveActivityTokenStorage`.
///
/// Stores a JSON dictionary of `activityType → tokenHex` in a file under Application
/// Support. Follows the same conventions as `FileLastLocationStateStore`:
/// - `completeUntilFirstUserAuthentication` data protection (readable in background after first unlock)
/// - excluded from iCloud/iTunes backups
/// - errors are swallowed; persistence is best-effort
/// - each public method is independently thread-safe via `NSLock`
///
/// `setPushToStartToken` performs its read-modify-write under a single lock acquisition,
/// so concurrent callers cannot interleave a load and a save.
final class FileActivityTokenStore: LiveActivityTokenStorage {
    private static let subdirectory = "io.customer.sdk.liveactivities"
    private static let filename = "pushToStartTokens.json"
    private static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    private let lock = NSLock()
    private let fileManager: FileManager
    private let directoryURL: URL?
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    /// - Parameters:
    ///   - fileManager: File manager used for I/O. Defaults to `.default`.
    ///   - directoryURL: Directory for the token file. If `nil`, uses Application Support
    ///     in the app container.
    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        jsonEncoder: JSONEncoder = JSONEncoder(),
        jsonDecoder: JSONDecoder = JSONDecoder()
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
        self.jsonEncoder = jsonEncoder
        self.jsonDecoder = jsonDecoder
    }

    func getPushToStartToken(activityType: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return load()?[activityType]
    }

    func setPushToStartToken(activityType: String, tokenHex: String) {
        lock.lock()
        defer { lock.unlock() }
        var tokens = load() ?? [:]
        tokens[activityType] = tokenHex
        save(tokens)
    }

    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        guard let url = fileURL(), fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }

    // MARK: - Private helpers (must be called from within a locked context)

    private func load() -> [String: String]? {
        guard let url = fileURL(),
              fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? jsonDecoder.decode([String: String].self, from: data)
    }

    private func save(_ tokens: [String: String]) {
        guard let data = try? jsonEncoder.encode(tokens),
              let url = fileURL()
        else { return }
        let directory = url.deletingLastPathComponent()
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: Self.protection]
        )
        setExcludedFromBackup(on: directory)
        do {
            try data.write(to: url, options: .atomic)
            try fileManager.setAttributes([.protectionKey: Self.protection], ofItemAtPath: url.path)
            setExcludedFromBackup(on: url)
        } catch {}
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
        guard let appSupport = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        return appSupport
            .appendingPathComponent(Self.subdirectory)
            .appendingPathComponent(Self.filename)
    }
}
