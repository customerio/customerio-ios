import Foundation

/// The floating notification-bell icon for the inbox, parsed from
/// `patterns.inbox.floatingIcon { background, color }`.
///
/// `background`/`color` are the container fill and glyph tint (hex strings). Any field may be
/// absent in a given branding response, so all are optional. The bell glyph itself is provided by
/// the renderer, so the raw SVG markup is intentionally not carried here.
struct InboxFloatingIcon: Equatable {
    /// Container background color (hex string), e.g. `#000000`.
    let background: String?
    /// Glyph tint color (hex string), e.g. `#ffffff`.
    let color: String?
}

/// Drop-shadow tokens for the inbox panel (`patterns.inbox.shadow`).
struct InboxShadow: Equatable {
    let color: String?
    let offsetX: Double?
    let offsetY: Double?
    let blur: Double?
}

/// Unread-indicator chrome (`patterns.inbox.unreadIndicator`).
///
/// `text` is preserved as a raw token dictionary (font/color tokens) so the renderer keeps the
/// full nested structure intact.
struct InboxUnreadIndicator: Equatable {
    let showAlert: Bool?
    let background: String?
    let text: [String: Any]?

    static func == (lhs: InboxUnreadIndicator, rhs: InboxUnreadIndicator) -> Bool {
        lhs.showAlert == rhs.showAlert &&
            lhs.background == rhs.background &&
            NSDictionary(dictionary: lhs.text ?? [:]).isEqual(to: rhs.text ?? [:])
    }
}

/// Strongly-typed inbox chrome parsed from `patterns.inbox`.
///
/// All fields are optional/tolerant of missing keys: a branding response that omits any of them
/// is valid, and the renderer falls back to its own defaults for whatever is nil.
struct InboxChrome: Equatable {
    /// The floating notification-bell icon (`patterns.inbox.floatingIcon`).
    let floatingIcon: InboxFloatingIcon
    let background: String?
    let cornerRadius: Double?
    let borderColor: String?
    let dividerColor: String?
    let shadow: InboxShadow?
    let position: String?
    let hoverBackground: String?
    let unreadIndicator: InboxUnreadIndicator?
}

/// Branding payload returned by `GET /api/v1/branding`.
///
/// Exposes theme tokens, the strongly-typed inbox `chrome` (bell icon styling + panel styling
/// parsed from `patterns.inbox`), and the optional dark-mode overrides (`patterns.modes.dark`).
/// Only the fields the overlay needs are kept; the raw inbox pattern passthrough is intentionally
/// dropped.
struct InboxBranding: Equatable {
    /// Theme tokens (colors, typography, spacing, etc.) keyed by token name.
    let theme: [String: Any]

    /// Strongly-typed inbox chrome (bell icon styling + panel styling) parsed from `patterns.inbox`.
    let chrome: InboxChrome

    /// `patterns.modes.dark` — dark-mode pattern overrides, if present.
    ///
    /// IMPORTANT: this key is OPTIONAL. It is ABSENT in the current server response, so it must
    /// parse to `nil` and callers must never assume it is present.
    let darkModePattern: [String: Any]?

    /// Parses the branding JSON object. Tolerant of missing keys throughout: any absent field
    /// yields `nil`/empty rather than failing. The field structs document the expected shape.
    static func from(jsonData: Data) -> InboxBranding? {
        guard let object = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            return nil
        }
        return from(object: object)
    }

    static func from(object: [String: Any]) -> InboxBranding {
        let theme = object["theme"] as? [String: Any] ?? [:]
        let patterns = object["patterns"] as? [String: Any] ?? [:]
        let inboxPattern = patterns["inbox"] as? [String: Any] ?? [:]

        // `patterns.modes.dark` is OPTIONAL. It is absent in this workspace's response, so this
        // resolves to nil — never assume it is present.
        let modes = patterns["modes"] as? [String: Any]
        let darkModePattern = modes?["dark"] as? [String: Any]

        return InboxBranding(
            theme: theme,
            chrome: parseChrome(inboxPattern),
            darkModePattern: darkModePattern
        )
    }

    /// Parses `patterns.inbox` into strongly-typed chrome. Every field is optional.
    private static func parseChrome(_ inbox: [String: Any]) -> InboxChrome {
        let iconObject = inbox["floatingIcon"] as? [String: Any] ?? [:]
        let floatingIcon = InboxFloatingIcon(
            background: iconObject["background"] as? String,
            color: iconObject["color"] as? String
        )

        let shadow = (inbox["shadow"] as? [String: Any]).map { shadowObject in
            InboxShadow(
                color: shadowObject["color"] as? String,
                offsetX: (shadowObject["offsetX"] as? NSNumber)?.doubleValue,
                offsetY: (shadowObject["offsetY"] as? NSNumber)?.doubleValue,
                blur: (shadowObject["blur"] as? NSNumber)?.doubleValue
            )
        }

        let unreadIndicator = (inbox["unreadIndicator"] as? [String: Any]).map { indicatorObject in
            InboxUnreadIndicator(
                showAlert: (indicatorObject["showAlert"] as? NSNumber)?.boolValue,
                background: indicatorObject["background"] as? String,
                text: indicatorObject["text"] as? [String: Any]
            )
        }

        return InboxChrome(
            floatingIcon: floatingIcon,
            background: inbox["background"] as? String,
            cornerRadius: (inbox["cornerRadius"] as? NSNumber)?.doubleValue,
            borderColor: inbox["borderColor"] as? String,
            dividerColor: inbox["dividerColor"] as? String,
            shadow: shadow,
            position: inbox["position"] as? String,
            hoverBackground: inbox["hoverBackground"] as? String,
            unreadIndicator: unreadIndicator
        )
    }

    static func == (lhs: InboxBranding, rhs: InboxBranding) -> Bool {
        NSDictionary(dictionary: lhs.theme).isEqual(to: rhs.theme) &&
            lhs.chrome == rhs.chrome &&
            NSDictionary(dictionary: lhs.darkModePattern ?? [:]).isEqual(to: rhs.darkModePattern ?? [:])
    }
}
