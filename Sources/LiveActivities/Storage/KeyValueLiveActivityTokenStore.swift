import CioInternalCommon
import Foundation

/// `LiveActivityTokenStorage` backed by the SDK's shared key-value storage — the same
/// UserDefaults-backed store that holds `installationId` and the push device token.
///
/// All per-activity-type signatures are persisted together as a single JSON
/// `[activityType: signature]` map under one key, so the store needs no schema and no
/// SQL layer. Reads and writes tolerate missing or corrupt data by treating the map as
/// empty; the only observable effect of a failure is that a push-to-start registration
/// may be re-sent on a future launch.
final class KeyValueLiveActivityTokenStore: LiveActivityTokenStorage {
    private let storage: SharedKeyValueStorage
    private let key: KeyValueStorageKey = .liveActivityRegistrations
    private let lock = NSLock()

    init(storage: SharedKeyValueStorage) {
        self.storage = storage
    }

    func registrationSignature(activityType: String) -> String? {
        lock.withLock { load()[activityType] }
    }

    func setRegistrationSignature(activityType: String, signature: String) {
        lock.withLock {
            var map = load()
            map[activityType] = signature
            save(map)
        }
    }

    func clearRegistrationSignature(activityType: String) {
        lock.withLock {
            var map = load()
            map[activityType] = nil
            save(map)
        }
    }

    func clearAll() {
        // Only remove our own key — `SharedKeyValueStorage.deleteAll()` would wipe the
        // entire shared store (installationId, device token, …).
        lock.withLock { storage.setString(nil, forKey: key) }
    }

    // MARK: - JSON map persistence

    private func load() -> [String: String] {
        guard let raw = storage.string(key),
              let data = raw.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return map
    }

    private func save(_ map: [String: String]) {
        guard let data = try? JSONEncoder().encode(map),
              let raw = String(data: data, encoding: .utf8)
        else { return }
        storage.setString(raw, forKey: key)
    }
}
