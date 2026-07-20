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

/// Result of routing a non-dismiss inbox action through the data layer, so the overlay knows
/// whether to run its default navigation.
@_spi(VisualInbox)
public enum VisualInboxActionOutcome: Equatable {
    /// The message was no longer in the store: nothing was tracked or offered to the host. The
    /// overlay must NOT run default navigation (the message — and its row — are gone).
    case messageMissing
    /// The host listener handled the action. The overlay should suppress its default navigation.
    case handledByHost
    /// The click was tracked but no host listener handled it. The overlay runs its default navigation.
    case notHandled
}

/// Inbox chrome colors (bell / panel / badge / divider) parsed from `patterns.inbox`, plus the
/// optional `patterns.modes.dark` raw overrides, handed to the overlay so it can drive its chrome
/// from backend branding instead of hardcoded colors. All hex strings are optional: a workspace that
/// hasn't configured inbox branding leaves them nil and the overlay falls back to its own defaults.
@_spi(VisualInbox)
public struct VisualInboxChrome: Equatable {
    /// `patterns.inbox.floatingIcon.background` — the bell circle fill.
    public let bellBackground: String?
    /// `patterns.inbox.floatingIcon.color` — the bell glyph tint.
    public let bellIconColor: String?
    /// `patterns.inbox.floatingIcon.svg` — raw SVG markup for the bell glyph. The overlay renders it
    /// (tinted by `bellIconColor`) and falls back to a bundled default bell when absent/unparseable.
    public let bellIconSvg: String?
    /// `patterns.inbox.background` — the panel surface.
    public let panelBackground: String?
    /// `patterns.inbox.dividerColor` (falling back to `borderColor`) — the row divider.
    public let dividerColor: String?
    /// `patterns.inbox.unreadIndicator.background` — the unread badge fill.
    public let badgeBackground: String?
    /// `patterns.inbox.unreadIndicator.text.color` — the unread badge count text color (hex string).
    /// nil when not configured; the overlay falls back to white.
    public let badgeTextColor: String?
    /// `patterns.inbox.unreadIndicator.text.fontSize` — the unread badge count text size (points).
    /// nil when not configured; the overlay falls back to its caption size.
    public let badgeTextSize: Double?
    /// `patterns.inbox.cornerRadius` — the panel corner radius (points).
    public let cornerRadius: Double?
    /// `patterns.inbox.position` — where the floating bell anchors (e.g. `bottom-right`, `bottom-left`,
    /// `top-right`, `top-left`). nil/unrecognized falls back to the overlay's default (bottom-right).
    /// Only positions the bell + badge; the slide-up panel always presents from the bottom edge.
    public let position: String?
    /// `patterns.inbox.unreadIndicator.showAlert` — whether the unread badge is shown at all. Web hides
    /// the badge when this is false (regardless of count). nil → default to showing it.
    public let showUnreadBadge: Bool?
    /// `patterns.modes.dark` raw overrides (OPTIONAL; nil in most workspaces). Resolved by the overlay
    /// only in dark mode, by digging the same keys nested under `dark.inbox`.
    public let darkModePattern: [String: Any]?

    public init(
        bellBackground: String?,
        bellIconColor: String?,
        bellIconSvg: String?,
        panelBackground: String?,
        dividerColor: String?,
        badgeBackground: String?,
        badgeTextColor: String?,
        badgeTextSize: Double?,
        cornerRadius: Double?,
        position: String?,
        showUnreadBadge: Bool?,
        darkModePattern: [String: Any]?
    ) {
        self.bellBackground = bellBackground
        self.bellIconColor = bellIconColor
        self.bellIconSvg = bellIconSvg
        self.panelBackground = panelBackground
        self.dividerColor = dividerColor
        self.badgeBackground = badgeBackground
        self.badgeTextColor = badgeTextColor
        self.badgeTextSize = badgeTextSize
        self.cornerRadius = cornerRadius
        self.position = position
        self.showUnreadBadge = showUnreadBadge
        self.darkModePattern = darkModePattern
    }

    public static func == (lhs: VisualInboxChrome, rhs: VisualInboxChrome) -> Bool {
        lhs.bellBackground == rhs.bellBackground &&
            lhs.bellIconColor == rhs.bellIconColor &&
            lhs.bellIconSvg == rhs.bellIconSvg &&
            lhs.panelBackground == rhs.panelBackground &&
            lhs.dividerColor == rhs.dividerColor &&
            lhs.badgeBackground == rhs.badgeBackground &&
            lhs.badgeTextColor == rhs.badgeTextColor &&
            lhs.badgeTextSize == rhs.badgeTextSize &&
            lhs.cornerRadius == rhs.cornerRadius &&
            lhs.position == rhs.position &&
            lhs.showUnreadBadge == rhs.showUnreadBadge &&
            NSDictionary(dictionary: lhs.darkModePattern ?? [:]).isEqual(to: rhs.darkModePattern ?? [:])
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
