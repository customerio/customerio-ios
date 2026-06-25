import CioInternalCommon
@_spi(VisualInbox) import CioMessagingInApp
import Foundation
#if canImport(SwiftUI)
import Jist
import SwiftUI

/// A single inbox message rendered via Jist (item 7).
///
/// Jist (`JistView`) requires iOS 15+. On iOS 13/14 we fall back to a minimal text row so the panel
/// stays usable below the Jist floor.
@available(iOS 13.0, *)
struct VisualInboxMessageRow: View {
    let message: VisualInboxMessageSnapshot
    /// The message's `properties` already decoded into Jist data by `VisualInboxModel` (decoded once
    /// per refresh, not per render).
    let data: [String: JistValue]
    let templates: [String: [JistTemplate]]
    let theme: [String: JistValue]
    /// Called when the message's Jist action resolves to a dismiss (item 1).
    let onDismiss: () -> Void
    /// Called when the message's Jist action is a NON-dismiss action (items 12/13). Carries the
    /// resolved action so the overlay can track the click, offer it to the host, and navigate.
    let onAction: (InboxActionResolution) -> Void

    var body: some View {
        Group {
            if #available(iOS 15.0, *) {
                JistView(
                    name: message.type,
                    templates: templates,
                    data: data,
                    theme: theme,
                    // Dark-mode parity (item 5): `.auto` follows the system color scheme.
                    mode: .auto,
                    // Relative dates (item 3): Jist passes an ISO-8601 string; we return web-aligned
                    // relative time ("just now", "2h ago", "3d ago").
                    formatDate: { iso, _ in Self.relativeDate(from: iso) },
                    onAction: handleAction
                )
            } else {
                fallbackRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// Minimal pre-iOS-15 row (below the Jist floor).
    private var fallbackRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(message.type)
                .font(.subheadline)
                .fontWeight(message.opened ? .regular : .semibold)
            Text(message.id)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Jist action handling (items 1, 12, 13)

    /// Maps a Jist `onAction` event to host behavior. Web parity: a "dismiss" action removes the
    /// message (item 1). Any other action is resolved (item 12 nav + item 13 host listener) and
    /// forwarded via `onAction`.
    ///
    /// The live inbox templates emit the action as `name == "messageAction"` with the message's
    /// `properties.messageAction` carrying either `{ behavior: "dismiss" }` (dismiss) or a
    /// `{ url, behavior }` for navigation. We also accept the Jist-demo dismiss sentinels
    /// (`name == "dismiss"` or `data.url == "#dismiss"`) as a fallback.
    private func handleAction(_ event: JistActionEvent) {
        if Self.isDismiss(event) {
            onDismiss()
            return
        }
        onAction(Self.resolve(event))
    }

    /// Whether the event resolves to a dismiss (kept EXACTLY as the original matching: data behavior
    /// `dismiss`, action name `dismiss`, or the `#dismiss` url sentinel).
    static func isDismiss(_ event: JistActionEvent) -> Bool {
        let behavior = event.data?.objectValue?["behavior"]?.stringValue
        let url = event.data?.objectValue?["url"]?.stringValue
        return behavior == "dismiss" || event.name == "dismiss" || url == "#dismiss"
    }

    /// Pure mapping from a non-dismiss Jist `onAction` event to an ``InboxActionResolution``. The
    /// action's url + behavior live in `event.data` (the message's `properties[name]`). Robust to
    /// missing/malformed fields — every field is optional and never force-unwrapped.
    static func resolve(_ event: JistActionEvent) -> InboxActionResolution {
        let data = event.data?.objectValue
        let url = data?["url"]?.stringValue
        let behavior: InboxActionResolution.Behavior
        switch data?["behavior"]?.stringValue {
        case "openUrl": behavior = .openUrl
        case "newTab": behavior = .newTab
        case "deeplink": behavior = .deeplink
        default: behavior = .none
        }
        // "Auto dismiss on click": a standalone `dismiss` flag (boolean true, or the string "true")
        // alongside a non-dismiss behavior means "run the action AND remove the message".
        let dismiss = data?["dismiss"]?.boolValue == true || data?["dismiss"]?.stringValue == "true"
        return InboxActionResolution(actionName: event.name, url: url, behavior: behavior, dismiss: dismiss)
    }

    // MARK: - Relative dates (item 3)

    private static let isoParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Fallback parser for ISO-8601 strings WITHOUT fractional seconds (the primary parser is strict
    /// about its option set, so a no-millisecond timestamp needs this variant).
    private static let isoParserNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// System-localized relative-time formatter (the platform equivalent of web's
    /// `Intl.RelativeTimeFormat`): produces translated output ("2 hours ago", "yesterday", …) in the
    /// device locale, so the inbox is i18n-ready without us hand-rolling/translating strings.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    /// Localized relative time from an ISO-8601 timestamp (translation-ready via the OS). Falls back
    /// to the raw string if it can't be parsed (so a row never renders worse than before).
    static func relativeDate(from iso: String, now: Date = Date()) -> String {
        guard let date = isoParser.date(from: iso) ?? isoParserNoFraction.date(from: iso) else {
            return iso
        }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }
}
#endif
