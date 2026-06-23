import CioInternalCommon
import Foundation

// MARK: - Visual Inbox cross-module SPI value types

// Plain Foundation value types the overlay UI module (`CioMessagingInbox`) renders from, gated behind
// `@_spi(VisualInbox)` so they stay off the public SDK surface. Split out of `VisualInboxSPI.swift`
// (the provider protocol + implementation) to keep each file within the file-length limit.

/// Visibility/loading signal the overlay renders from. Mirrors the internal `VisualInboxLoadState`
/// but is a self-contained SPI value type (no internal types leak across the module boundary).
@_spi(VisualInbox)
public enum VisualInboxState: Equatable {
    /// Nothing fetched yet for the current user.
    case idle
    /// A fetch is in flight — the overlay shows a loading affordance.
    case loading
    /// Fully renderable: enabled, with messages + templates + branding all available.
    case visible(messageCount: Int)
    /// Not renderable (disabled, or any of messages/templates/branding missing). The overlay hides
    /// all chrome. `reason` is diagnostic only. This is NOT an error state.
    case hidden(reason: String)

    /// Whether the overlay should show the inbox chrome (bell + panel).
    public var isVisible: Bool {
        if case .visible = self { return true }
        return false
    }
}

/// A single inbox message, flattened to the minimum the overlay needs to render it via Jist.
///
/// `properties` is preserved as a typed `[String: Any]` (nested objects/arrays/numbers/bools/dates
/// intact — no string flattening) so the overlay can decode it into Jist's `[String: JistValue]`.
@_spi(VisualInbox)
public struct VisualInboxMessageSnapshot: Identifiable {
    /// Stable identifier (the underlying message's queueId).
    public let id: String
    /// Jist message type — selects a template from the registry.
    public let type: String
    /// Typed, nested-preserving properties handed to the Jist renderer.
    public let properties: [String: Any]
    /// Whether the user has opened this message.
    public let opened: Bool
    /// Original send time.
    public let sentAt: Date

    public init(id: String, type: String, properties: [String: Any], opened: Bool, sentAt: Date) {
        self.id = id
        self.type = type
        self.properties = properties
        self.opened = opened
        self.sentAt = sentAt
    }
}

/// A single coalesced snapshot of everything the overlay renders from, emitted by
/// ``VisualInboxProvider/observe()`` whenever the underlying data layer changes.
///
/// Bundling state + messages + count + rendering inputs into one value lets the overlay model
/// publish atomically (one `@Published` write per emission) and lets the provider de-dupe emissions
/// (only forward an emission when the snapshot actually differs from the last one).
@_spi(VisualInbox)
public struct VisualInboxSnapshot: Equatable {
    public let state: VisualInboxState
    public let messages: [VisualInboxMessageSnapshot]
    public let unopenedCount: Int
    /// Raw templates registry JSON, decoded by the overlay into Jist types.
    public let templatesJSON: [String: Any]?
    /// Raw branding theme JSON, decoded by the overlay into Jist types.
    public let themeJSON: [String: Any]?

    public init(
        state: VisualInboxState,
        messages: [VisualInboxMessageSnapshot],
        unopenedCount: Int,
        templatesJSON: [String: Any]?,
        themeJSON: [String: Any]?
    ) {
        self.state = state
        self.messages = messages
        self.unopenedCount = unopenedCount
        self.templatesJSON = templatesJSON
        self.themeJSON = themeJSON
    }

    /// Structural equality used purely to de-dupe emissions. Compares every render-affecting field:
    /// state, count, per-message identity/opened/type AND the render payload (each message's
    /// `properties` plus the raw `templatesJSON`/`themeJSON`). Content-only changes — e.g. a Jist row's
    /// properties or an updated template/theme arriving while `state`/ids are unchanged — must count as
    /// DIFFERENT so `emitSnapshot` forwards them; otherwise `VisualInboxModel.apply` keeps rendering
    /// stale rows/theme. The `[String: Any]` dictionaries aren't `Equatable`, so they're compared via
    /// `NSDictionary(dictionary:).isEqual`, mirroring `InboxBranding`/`InboxTemplatesRegistry`.
    public static func == (lhs: VisualInboxSnapshot, rhs: VisualInboxSnapshot) -> Bool {
        lhs.state == rhs.state &&
            lhs.unopenedCount == rhs.unopenedCount &&
            lhs.messages.count == rhs.messages.count &&
            zip(lhs.messages, rhs.messages).allSatisfy { l, r in
                l.id == r.id && l.opened == r.opened && l.type == r.type &&
                    NSDictionary(dictionary: l.properties).isEqual(to: r.properties)
            } &&
            jsonEqual(lhs.templatesJSON, rhs.templatesJSON) &&
            jsonEqual(lhs.themeJSON, rhs.themeJSON)
    }

    /// Compares two optional `[String: Any]` render-payload dictionaries (nil == nil, nil != non-nil),
    /// using `NSDictionary.isEqual` for the non-nil case (same approach as the data-layer types).
    private static func jsonEqual(_ lhs: [String: Any]?, _ rhs: [String: Any]?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (let l?, let r?): return NSDictionary(dictionary: l).isEqual(to: r)
        default: return false
        }
    }
}
