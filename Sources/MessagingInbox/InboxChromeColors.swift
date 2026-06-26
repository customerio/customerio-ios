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
@available(iOS 13.0, *)
struct ResolvedInboxColors {
    let bellBackground: Color
    let bellIcon: Color
    let panelBackground: Color
    let divider: Color
    let badge: Color
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

        let cornerRadius = CGFloat(chrome?.cornerRadius ?? 12)

        return ResolvedInboxColors(
            bellBackground: bellBackground,
            bellIcon: bellIcon,
            panelBackground: panelBackground,
            divider: divider,
            badge: badge,
            cornerRadius: cornerRadius
        )
    }
}

/// Parses branding hex color strings into SwiftUI colors. iOS 13-safe: builds `Color` directly from
/// sRGB components (no `UIColor(_:)`/`Color` round-trip, which is iOS 14+) and computes luminance from
/// the same components.
@available(iOS 13.0, *)
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
}
#endif
