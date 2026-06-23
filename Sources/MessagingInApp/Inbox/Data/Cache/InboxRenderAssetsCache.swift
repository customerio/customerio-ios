import CioInternalCommon
import Foundation

/// Workspace-scoped persistent store for the visual-inbox render assets (templates JSON, branding
/// JSON, and the enablement flag).
///
/// Backed by the same `SharedKeyValueStorage` the headless inbox uses to persist its queue response
/// body, so render assets survive process restarts and reuse the existing storage mechanism rather
/// than a bespoke in-memory store. Entries are workspace-scoped (the underlying UserDefaults file is
/// keyed by site id), not per-user.
///
/// There is **no wall-clock TTL/expiry**: freshness is decided by once-per-session server
/// revalidation in `VisualInboxRepository`, matching Android's model. This store's sole job is to
/// hold the **last-known payload** so it can be served on a subsequent (same-session) read without a
/// network call, and served stale when a revalidation fails.
struct InboxRenderAssetsCache {
    private let keyValueStore: SharedKeyValueStorage

    init(keyValueStore: SharedKeyValueStorage) {
        self.keyValueStore = keyValueStore
    }

    // MARK: - Raw payloads (templates / branding)

    /// Persists the last-known `data` for `key`. Overwrites any previously stored payload.
    func setData(_ data: Data, forKey key: KeyValueStorageKey) {
        keyValueStore.setData(data, forKey: key)
    }

    /// Returns the last-known payload for `key`, or nil if none has been stored. Never expires.
    func data(forKey key: KeyValueStorageKey) -> Data? {
        keyValueStore.data(key)
    }

    // MARK: - Enabled flag

    func setEnabled(_ enabled: Bool) {
        keyValueStore.setInt(enabled ? 1 : 0, forKey: .inboxEnabledFlag)
    }

    /// The last-known enablement flag, or nil if it has never been recorded.
    func enabledFlag() -> Bool? {
        guard let raw = keyValueStore.integer(.inboxEnabledFlag) else { return nil }
        return raw != 0
    }
}
