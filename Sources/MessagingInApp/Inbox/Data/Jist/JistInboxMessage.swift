import Foundation

/// Jist-facing representation of an inbox message produced by `InboxMessageJistAdapter`.
///
/// Jist renders from a message's `type` + `properties`, combined with the server-provided
/// templates registry and branding theme. This adapter output deliberately keeps `properties`
/// as a typed `[String: Any]` — nested objects, arrays, bools, numbers, and dates are preserved
/// exactly, with **no String flattening**. (The spike's adapter that flattened everything to
/// strings does not exist on this branch and must not be reintroduced.)
struct JistInboxMessage: Equatable {
    /// Stable identifier carried through from the inbox message.
    let queueId: String
    /// Jist message type used to select a template from the registry.
    let type: String
    /// Typed, nested-preserving properties handed to the Jist renderer.
    let properties: [String: Any]
    /// Whether the user has opened the message (carried through for UI state).
    let opened: Bool
    /// Original send time.
    let sentAt: Date
    /// Optional priority (lower = higher priority).
    let priority: Int?

    static func == (lhs: JistInboxMessage, rhs: JistInboxMessage) -> Bool {
        lhs.queueId == rhs.queueId &&
            lhs.type == rhs.type &&
            lhs.opened == rhs.opened &&
            lhs.sentAt == rhs.sentAt &&
            lhs.priority == rhs.priority &&
            NSDictionary(dictionary: lhs.properties).isEqual(to: rhs.properties)
    }
}

/// Maps domain `InboxMessage` values to `JistInboxMessage` for the Jist renderer.
///
/// Critical invariant: `properties` is passed through untouched. The domain model already
/// preserves `[String: Any]` (see `InboxMessageResponse`/`InboxMessage`), and this adapter must
/// not coerce nested values into strings.
enum InboxMessageJistAdapter {
    static func toJist(_ message: InboxMessage) -> JistInboxMessage {
        JistInboxMessage(
            queueId: message.queueId,
            type: message.type,
            // Pass-through: preserves nested objects/arrays/bools/numbers/dates as-is.
            properties: message.properties,
            opened: message.opened,
            sentAt: message.sentAt,
            priority: message.priority
        )
    }

    static func toJist(_ messages: [InboxMessage]) -> [JistInboxMessage] {
        messages.map(toJist)
    }
}
