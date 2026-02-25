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
    // Location guardrails: cached location and last synced (for 24h + 1 km filter)
    case locationCachedLatitude
    case locationCachedLongitude
    case locationLastSyncedLatitude
    case locationLastSyncedLongitude
    case locationLastSyncedTimestamp
}
