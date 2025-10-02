import Foundation

/**
 The keys for `KeyValueStorage`. Less error-prone then hard-coded strings.
 */
public enum KeyValueStorageKey: String {
    case identifiedProfileId
    case pushDeviceToken
    case inAppUserQueueFetchCachedResponse
    // Anonymous message storage keys (using "broadcast_" prefix for backward compatibility)
    case broadcastMessages = "broadcast_messages"
    case broadcastMessagesExpiry = "broadcast_messages_expiry"
}
