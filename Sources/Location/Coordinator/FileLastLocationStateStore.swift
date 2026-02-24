import CioInternalCommon
import Foundation

/// Persists `LastLocationState` in a file with iOS Data Protection (encrypted at rest).
/// Data is cleared when the app is uninstalled. No Keychain or iCloud sync.
///
/// Uses `completeUntilFirstUserAuthentication` so the cache can be read when the app is in the background (e.g. after the user has unlocked the device once this boot).
///
/// ## Error scenarios
///
/// The store treats persistence as best-effort and does not throw or surface errors to callers.
///
/// **load():**
/// - **No Application Support URL** (e.g. unsupported environment): `stateFileURL()` returns `nil` → `load()` returns `nil`.
/// - **File does not exist**: Returns `nil` (same as empty cache).
/// - **Read permission / I/O error**: `Data(contentsOf:)` fails → `load()` returns `nil`.
/// - **Corrupt or incompatible JSON**: Decode fails → `load()` returns `nil`. Caller should treat as no cache and may overwrite on next save.
/// - **Data protection block** (device locked before first unlock): Read can fail → `load()` returns `nil`. Resolves after user unlocks once.
///
/// **save(_:):**
/// - **Encode failure** (e.g. non‑Encodable state): Guard fails → save is skipped; no write.
/// - **No Application Support URL**: `stateFileURL()` returns `nil` → save is skipped.
/// - **Directory creation fails** (e.g. disk full, permission): Directory may be missing → subsequent write can fail; error swallowed.
/// - **Write or setAttributes fails** (e.g. disk full, permission, volume read‑only): Error caught and ignored; previous file content (if any) is unchanged.
///
/// **clear():**
/// - **File does not exist**: No-op; returns without error.
/// - **Remove fails** (e.g. permission): Error ignored; file may still exist. Next `load()` could still return data.
///
/// ## Thread safety
///
/// Each of `load()`, `save(_:)`, and `clear()` is thread-safe. Read-modify-write sequences (e.g. load then save) are not atomic at the store level; a caller that does load→modify→save must serialize that sequence to avoid lost updates. `LastLocationStorageImpl` does this by holding a lock for each of its methods so that concurrent calls to e.g. `setCachedLocation` and `recordLastSync` do not overwrite each other.
final class FileLastLocationStateStore: LastLocationStateStore {
    private static let subdirectory = "io.customer.sdk.location"
    private static let filename = "lastLocationState.json"
    private static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    private let lock = NSLock()
    private let fileManager: FileManager
    private let directoryURL: URL?
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    /// - Parameters:
    ///   - fileManager: File manager used for I/O. Defaults to `.default`.
    ///   - directoryURL: Directory for the state file. If `nil`, uses Application Support in the app container.
    ///   - jsonEncoder: Encoder for state. Default uses secondsSince1970 for dates.
    ///   - jsonDecoder: Decoder for state. Default uses secondsSince1970 for dates.
    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        jsonEncoder: JSONEncoder = FileLastLocationStateStore.makeEncoder(),
        jsonDecoder: JSONDecoder = FileLastLocationStateStore.makeDecoder()
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
        self.jsonEncoder = jsonEncoder
        self.jsonDecoder = jsonDecoder
    }

    func load() -> LastLocationState? {
        lock.lock()
        defer { lock.unlock() }
        guard let url = stateFileURL() else { return nil }
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? jsonDecoder.decode(LastLocationState.self, from: data)
    }

    func save(_ state: LastLocationState) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? jsonEncoder.encode(state),
              let url = stateFileURL()
        else {
            return
        }
        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: Self.protection]
            )
        }
        do {
            try data.write(to: url, options: .atomic)
            try fileManager.setAttributes(
                [.protectionKey: Self.protection],
                ofItemAtPath: url.path
            )
        } catch {
            // Avoid exposing file system errors to callers; persistence is best-effort.
        }
    }

    private func stateFileURL() -> URL? {
        if let directory = directoryURL {
            return directory.appendingPathComponent(Self.filename)
        }
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport
            .appendingPathComponent(Self.subdirectory)
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

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        guard let url = stateFileURL(), fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }
}
