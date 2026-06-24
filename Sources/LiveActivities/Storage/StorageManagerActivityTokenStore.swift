import CioInternalCommon
import Foundation

/// `LiveActivityTokenStorage` backed by the shared encrypted `StorageManager`.
///
/// When `storage` is `nil` (e.g. SDK not yet initialised), all operations are
/// no-ops: `getPushToStartToken` returns `nil` and writes are silently dropped.
/// The only observable effect is that push-to-start tokens are re-sent to the
/// backend on every launch until a `StorageManager` is available.
final class StorageManagerActivityTokenStore: LiveActivityTokenStorage {
    private let storage: StorageManager?

    init(storage: StorageManager?) {
        self.storage = storage
    }

    func getPushToStartToken(activityType: String) -> String? {
        try? storage?.getLiveActivityPushToken(activityType: activityType)
    }

    func setPushToStartToken(activityType: String, tokenHex: String) {
        try? storage?.setLiveActivityPushToken(activityType: activityType, tokenHex: tokenHex)
    }

    func clearAll() {
        try? storage?.clearAllLiveActivityPushTokens()
    }
}
