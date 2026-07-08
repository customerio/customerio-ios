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
///
/// `delivered` dedup markers are kept in a **separate** `[deliveryId: epochMillis]` map under
/// their own key, so the hot registration-signature lookups (run on every device-token/user
/// change) never deserialize the delivery history. The delivery map is TTL-bounded (see
/// `hasFreshDeliveredMarker`).
final class KeyValueLiveActivityTokenStore: LiveActivityTokenStorage {
    private let storage: SharedKeyValueStorage
    private let key: KeyValueStorageKey = .liveActivityRegistrations
    private let deliveredKey: KeyValueStorageKey = .liveActivityDeliveries
    private let lock = NSLock()

    /// Cap on retained `delivered` markers after TTL pruning — defense-in-depth against a burst of
    /// unique deliveries inside the TTL window. When exceeded, the oldest markers are evicted.
    private static let deliveredMarkerCap = 500

    /// One-shot guard so the O(n) TTL trim runs once per process (first delivered-marker access),
    /// not on every push. Guarded by `lock`.
    private var didPruneDelivered = false

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

    func allRegistrationKeys() -> [String] {
        lock.withLock { Array(load().keys) }
    }

    func clearAll() {
        // Only remove our own keys — `SharedKeyValueStorage.deleteAll()` would wipe the
        // entire shared store (installationId, device token, …).
        lock.withLock {
            storage.setString(nil, forKey: key)
            storage.setString(nil, forKey: deliveredKey)
        }
    }

    // MARK: - Delivered dedup markers (separate, TTL-bounded map)

    func hasFreshDeliveredMarker(_ deliveryId: String, ttl: TimeInterval) -> Bool {
        lock.withLock {
            var map = loadDelivered()
            if pruneDeliveredIfNeeded(&map, ttl: ttl) {
                saveDelivered(map)
            }
            guard let millis = map[deliveryId] else { return false }
            let ageSeconds = Date().timeIntervalSince1970 - Double(millis) / 1000
            return ageSeconds <= ttl
        }
    }

    func setDeliveredMarker(_ deliveryId: String, at date: Date) {
        lock.withLock {
            var map = loadDelivered()
            map[deliveryId] = Int64((date.timeIntervalSince1970 * 1000).rounded())
            capDelivered(&map)
            saveDelivered(map)
        }
    }

    /// Drops markers older than `ttl`. Runs at most once per process (first delivered-marker
    /// access). Returns whether the map changed and therefore needs persisting.
    private func pruneDeliveredIfNeeded(_ map: inout [String: Int64], ttl: TimeInterval) -> Bool {
        guard !didPruneDelivered else { return false }
        didPruneDelivered = true
        let cutoffMillis = Int64((Date().timeIntervalSince1970 - ttl) * 1000)
        let before = map.count
        map = map.filter { $0.value >= cutoffMillis }
        return map.count != before
    }

    /// Backstop: keep only the newest `deliveredMarkerCap` markers by timestamp.
    private func capDelivered(_ map: inout [String: Int64]) {
        guard map.count > Self.deliveredMarkerCap else { return }
        let newest = map.sorted { $0.value > $1.value }.prefix(Self.deliveredMarkerCap)
        map = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
    }

    func resolveInstanceId(forActivityId activityId: String, orCreate: () -> String) -> String {
        lock.withLock {
            var map = load()
            let mapKey = Self.instanceIdKey(activityId)
            if let existing = map[mapKey] { return existing }
            let created = orCreate()
            map[mapKey] = created
            save(map)
            return created
        }
    }

    func clearInstanceId(forActivityId activityId: String) {
        lock.withLock {
            var map = load()
            map[Self.instanceIdKey(activityId)] = nil
            save(map)
        }
    }

    /// Namespaced key for an `Activity.id` → instance id mapping, so it can't collide with a
    /// registration signature (bare activity type / `instance:` / `ptsvalue:` keys).
    private static func instanceIdKey(_ activityId: String) -> String {
        "aid:" + activityId
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

    private func loadDelivered() -> [String: Int64] {
        guard let raw = storage.string(deliveredKey),
              let data = raw.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: Int64].self, from: data)
        else { return [:] }
        return map
    }

    private func saveDelivered(_ map: [String: Int64]) {
        guard let data = try? JSONEncoder().encode(map),
              let raw = String(data: data, encoding: .utf8)
        else { return }
        storage.setString(raw, forKey: deliveredKey)
    }
}
