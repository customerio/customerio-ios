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
    // Visual-inbox render assets, persisted (workspace-scoped) using the same key-value mechanism the
    // headless inbox uses for its queue response body. These hold the last-known payloads (no
    // wall-clock expiry); freshness is decided by once-per-session server revalidation, not a TTL.
    case inboxTemplatesCache = "inbox_templates_cache"
    case inboxBrandingCache = "inbox_branding_cache"
    case inboxEnabledFlag = "inbox_enabled_flag"
}
