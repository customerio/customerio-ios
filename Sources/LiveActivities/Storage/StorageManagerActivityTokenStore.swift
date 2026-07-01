import CioInternalCommon
import Foundation

/// `LiveActivityTokenStorage` backed by the shared encrypted `StorageManager`.
///
/// When `storage` is `nil` (e.g. SDK not yet initialised), reads return `nil` and writes
/// are silently dropped. The only observable effect is that a push-to-start registration
/// may be re-sent on a future launch until a `StorageManager` is available.
final class StorageManagerActivityTokenStore: LiveActivityTokenStorage {
    private let storage: StorageManager?

    init(storage: StorageManager?) {
        self.storage = storage
    }

    func registrationSignature(activityType: String) -> String? {
        (try? storage?.getRegistrationSignature(activityType: activityType)) ?? nil
    }

    func setRegistrationSignature(activityType: String, signature: String) {
        try? storage?.setRegistrationSignature(activityType: activityType, signature: signature)
    }

    func clearAll() {
        try? storage?.clearAllLiveActivityRegistrations()
    }
}
