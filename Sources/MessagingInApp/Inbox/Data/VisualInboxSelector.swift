import Foundation

/// Dedicated selection/ordering for the **visual** inbox.
///
/// This is intentionally separate from `DefaultNotificationInbox`'s headless filtering
/// (case-insensitive exact-match topic + sentAt-desc only) so the visual overlay can apply its
/// own rules without disturbing the existing headless ordering:
///  - Topic filter uses the `cio_inbox` **prefix** (not exact-match).
///  - Sort by priority ascending (lower value = higher priority; nil priority sorts last),
///    then sentAt descending.
///  - Messages whose `expiry` has passed at read time are dropped.
enum VisualInboxSelector {
    /// Topic prefix that marks a message as belonging to the visual inbox.
    static let visualInboxTopicPrefix = "cio_inbox"

    /// Selects, filters, and sorts messages for the visual inbox.
    /// - Parameters:
    ///   - messages: All inbox messages from state.
    ///   - now: Reference time used for expiry evaluation (injectable for tests).
    /// - Returns: visual-inbox messages, expired entries removed, sorted priority asc → sentAt desc.
    static func select(messages: [InboxMessage], now: Date = Date()) -> [InboxMessage] {
        messages
            .filter { hasVisualInboxTopic($0) }
            .filter { !isExpired($0, now: now) }
            .sorted(by: orderedBefore)
    }

    /// A message belongs to the visual inbox if any of its topics begins with the `cio_inbox` prefix.
    /// Matching is case-insensitive to be tolerant of server casing.
    static func hasVisualInboxTopic(_ message: InboxMessage) -> Bool {
        message.topics.contains { $0.lowercased().hasPrefix(visualInboxTopicPrefix) }
    }

    /// Whether the message has expired relative to `now`. Messages without an expiry never expire.
    static func isExpired(_ message: InboxMessage, now: Date) -> Bool {
        guard let expiry = message.expiry else { return false }
        return expiry <= now
    }

    /// Sort comparator: priority ascending (nil last), then sentAt descending.
    private static func orderedBefore(_ lhs: InboxMessage, _ rhs: InboxMessage) -> Bool {
        switch (lhs.priority, rhs.priority) {
        case (let l?, let r?) where l != r:
            return l < r
        case (nil, _?):
            return false // lhs has no priority, rhs does -> rhs first
        case (_?, nil):
            return true // lhs has priority, rhs doesn't -> lhs first
        default:
            // Equal priority (or both nil): newest first.
            return lhs.sentAt > rhs.sentAt
        }
    }
}
