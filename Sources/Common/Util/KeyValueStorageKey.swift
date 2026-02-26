import Foundation

/**
 The keys for `KeyValueStorage`. Less error-prone then hard-coded strings.
 */
public enum KeyValueStorageKey: String {
    case identifiedProfileId
    case pushDeviceToken
    case inAppUserQueueFetchCachedResponse
    case broadcastMessages = "broadcast_messages"
    case broadcastMessagesExpiry = "broadcast_messages_expiry"
    case broadcastMessagesTracking = "broadcast_messages_tracking"
    case inboxMessagesOpenedStatus = "inbox_messages_opened_status"
}
