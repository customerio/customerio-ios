@_spi(VisualInbox) import CioMessagingInApp
import Foundation
#if canImport(SwiftUI)
import CoreGraphics
import SwiftUI

/// Resolved chrome colors for the overlay, driven by backend branding so they are configurable per
/// workspace across all consumer apps.
///
/// Every value is resolved in this priority order, with the SwiftUI/system defaults serving only as a
/// last-resort floor:
///   1. `patterns.modes.dark.inbox.*` — dark mode only, AND only when the workspace configured a dark
///      palette (`patterns.modes.dark` is OPTIONAL; absent in most workspaces),
///   2. `patterns.inbox.*` — the workspace's configured (light) inbox chrome,
///   3. a SwiftUI/system default (`Color.accentColor` / `Color(.systemBackground)` / `Color.red` …).
struct ResolvedInboxColors {
    let bellBackground: Color
    let bellIcon: Color
    let panelBackground: Color
    let divider: Color
    let badge: Color
    /// Unread badge count text color (branding `unreadIndicator.text.color`, else white).
    let badgeText: Color
    /// Unread badge count text size in points (branding `unreadIndicator.text.fontSize`), or nil to
    /// fall back to the caption font.
    let badgeTextSize: CGFloat?
    let cornerRadius: CGFloat

    /// Resolves the chrome colors from the SPI `chrome` payload for the current color scheme.
    static func resolve(chrome: VisualInboxChrome?, isDark: Bool) -> ResolvedInboxColors {
        // Dark overrides are an OPTIONAL raw map (shape mirrors patterns.inbox, nested under
        // modes.dark.inbox). Only consulted in dark mode; absent workspaces fall through to `chrome`.
        let darkInbox: [String: Any]? = isDark ? (chrome?.darkModePattern?["inbox"] as? [String: Any]) : nil

        let bellBackgroundHex = darkInbox.childString("floatingIcon", "background") ?? chrome?.bellBackground
        let bellBackground = InboxColorParser.color(from: bellBackgroundHex) ?? .accentColor

        let bellIconHex = darkInbox.childString("floatingIcon", "color") ?? chrome?.bellIconColor
        let bellIcon: Color
        if let parsed = InboxColorParser.color(from: bellIconHex) {
            bellIcon = parsed
        } else if let luminance = InboxColorParser.luminance(of: bellBackgroundHex) {
            // Final fallback when the bell background came from branding: contrast against it so a
            // light branded bell never gets a white glyph on a white circle.
            bellIcon = luminance > 0.5 ? .black : .white
        } else {
            // No branded bell background to measure (system accent fallback): white reads well on the
            // default accent across light/dark.
            bellIcon = .white
        }

        let panelHex = darkInbox.string("background") ?? chrome?.panelBackground
        let panelBackground = InboxColorParser.color(from: panelHex) ?? Color(.systemBackground)

        let dividerHex = darkInbox.string("dividerColor") ?? darkInbox.string("borderColor") ?? chrome?.dividerColor
        let divider = InboxColorParser.color(from: dividerHex) ?? Color(.separator)

        let badgeHex = darkInbox.childString("unreadIndicator", "background") ?? chrome?.badgeBackground
        let badge = InboxColorParser.color(from: badgeHex) ?? .red

        // Badge count text color/size from branding `unreadIndicator.text` (MBL-2126). The dark
        // override (when present) nests as `unreadIndicator.text.{color,fontSize}`; each falls back
        // to the light chrome value, then to white / caption.
        let badgeTextHex = darkInbox.grandchildString("unreadIndicator", "text", "color") ?? chrome?.badgeTextColor
        let badgeText = InboxColorParser.color(from: badgeTextHex) ?? .white
        let badgeTextSize = (darkInbox.grandchildDouble("unreadIndicator", "text", "fontSize") ?? chrome?.badgeTextSize)
            .map { CGFloat($0) }

        let cornerRadius = CGFloat(chrome?.cornerRadius ?? 12)

        return ResolvedInboxColors(
            bellBackground: bellBackground,
            bellIcon: bellIcon,
            panelBackground: panelBackground,
            divider: divider,
            badge: badge,
            badgeText: badgeText,
            badgeTextSize: badgeTextSize,
            cornerRadius: cornerRadius
        )
    }
}

/// Parses branding hex color strings directly from sRGB components so color construction and
/// luminance calculations use the same normalized values.
enum InboxColorParser {
    /// Normalized sRGB components parsed from a hex string.
    private struct RGBA {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    /// `#RRGGBB` or `#RRGGBBAA` (CSS byte order) → SwiftUI `Color`, or nil when absent / malformed.
    static func color(from hex: String?) -> Color? {
        guard let rgba = rgba(from: hex) else { return nil }
        return Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }

    /// Rec. 601 relative luminance (0…1) of a hex color, or nil when absent / malformed.
    static func luminance(of hex: String?) -> Double? {
        guard let rgba = rgba(from: hex) else { return nil }
        return 0.299 * rgba.red + 0.587 * rgba.green + 0.114 * rgba.blue
    }

    private static func rgba(from hex: String?) -> RGBA? {
        guard var value = hex?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if value.hasPrefix("#") { value.removeFirst() }
        guard let bits = UInt64(value, radix: 16) else { return nil }
        switch value.count {
        case 6:
            return RGBA(
                red: Double((bits >> 16) & 0xFF) / 255,
                green: Double((bits >> 8) & 0xFF) / 255,
                blue: Double(bits & 0xFF) / 255,
                alpha: 1
            )
        case 8:
            return RGBA(
                red: Double((bits >> 24) & 0xFF) / 255,
                green: Double((bits >> 16) & 0xFF) / 255,
                blue: Double((bits >> 8) & 0xFF) / 255,
                alpha: Double(bits & 0xFF) / 255
            )
        default:
            return nil
        }
    }
}

/// Small helpers for digging string values out of the optional `patterns.modes.dark.inbox` raw map.
private extension Optional where Wrapped == [String: Any] {
    /// A top-level String value, or nil.
    func string(_ key: String) -> String? {
        self?[key] as? String
    }

    /// A String from a nested child object (e.g. `floatingIcon.background`), or nil.
    func childString(_ child: String, _ key: String) -> String? {
        (self?[child] as? [String: Any])?[key] as? String
    }

    /// A String from a doubly-nested object (e.g. `unreadIndicator.text.color`), or nil.
    func grandchildString(_ child: String, _ grandchild: String, _ key: String) -> String? {
        ((self?[child] as? [String: Any])?[grandchild] as? [String: Any])?[key] as? String
    }

    /// A Double from a doubly-nested object (e.g. `unreadIndicator.text.fontSize`), or nil.
    /// Accepts an NSNumber (the usual JSON case) or a numeric String.
    func grandchildDouble(_ child: String, _ grandchild: String, _ key: String) -> Double? {
        let value = ((self?[child] as? [String: Any])?[grandchild] as? [String: Any])?[key]
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
#endif
