import CioInternalCommon
import Foundation

/// Persistent store for the visual-inbox render assets (templates JSON, branding JSON, and the
/// enablement flag).
///
/// Backed by the same `SharedKeyValueStorage` the headless inbox uses to persist its queue response
/// body, so render assets survive process restarts and reuse the existing storage mechanism rather
/// than a bespoke in-memory store.
///
/// Scope: entries are **app-wide**, not per-user and not per-workspace. `SharedKeyValueStorage`
/// resolves to a single shared UserDefaults suite with no site id in its name, unlike the
/// site-scoped storage used elsewhere in the SDK. Cross-user carryover is handled by clearing on
/// logout (see `clear()`); re-initializing the SDK with a different site id in one process would
/// still read the previous workspace's assets until the next revalidation overwrites them.
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

    // MARK: - Clearing

    /// Drops every persisted render asset and the enablement flag.
    ///
    /// Called on logout: these are workspace-scoped rather than per-user, so leaving them behind
    /// would serve one user's inbox to the next.
    func clear() {
        clearRenderAssets()
        keyValueStore.setInt(nil, forKey: .inboxEnabledFlag)
    }

    /// Drops the templates/branding payloads but keeps the enablement flag.
    ///
    /// Used when a revalidation completes after the session it belonged to ended: its payloads must
    /// not survive, but the current session's enablement — possibly already re-established by a
    /// later poll — must.
    func clearRenderAssets() {
        keyValueStore.setData(nil, forKey: .inboxTemplatesCache)
        keyValueStore.setData(nil, forKey: .inboxBrandingCache)
    }
}
