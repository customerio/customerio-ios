import CioInternalCommon
@_spi(VisualInbox) import CioMessagingInApp
import Foundation
#if canImport(SwiftUI)
import Jist
import SwiftUI
import UIKit

/// A SwiftUI overlay that renders the Visual Notification Inbox on top of your app.
///
/// Mount it anywhere in your hierarchy (typically pinned to a corner via a `ZStack`). It renders a
/// floating bell button with an unread-count badge plus a slide-out panel that lists inbox messages,
/// each rendered natively via **Jist** from the server-provided templates + branding theme.
///
/// ## Usage
/// ```swift
/// ZStack { MyDashboard(); NotificationInboxOverlay() }
/// ```
@available(iOS 13.0, *)
public struct NotificationInboxOverlay: View {
    @StateObject private var model: VisualInboxModel

    /// True when the slide-out panel is visible.
    @State private var isPanelOpen: Bool = false

    /// Vertical inset that keeps the slide-out panel clear of the floating button.
    private let panelBottomInset: CGFloat = 88

    /// Called whenever the slide-out panel opens (`true`) or closes (`false`). Hosts that mount the
    /// overlay in a passthrough window use this to capture touches full-screen while the panel is
    /// open (so the scrim blocks click-through) and pass through when it's closed.
    private let onPanelPresentationChange: ((Bool) -> Void)?

    /// Creates an inbox overlay backed by the SDK's shared Visual Inbox data layer.
    /// - Parameter onPanelPresentationChange: optional callback invoked when the panel opens/closes.
    public init(onPanelPresentationChange: ((Bool) -> Void)? = nil) {
        _model = StateObject(wrappedValue: VisualInboxModel())
        self.onPanelPresentationChange = onPanelPresentationChange
    }

    /// Creates an inbox overlay backed by the supplied model. Used by tests/previews to inject a fake.
    init(model: VisualInboxModel, onPanelPresentationChange: ((Bool) -> Void)? = nil) {
        _model = StateObject(wrappedValue: model)
        self.onPanelPresentationChange = onPanelPresentationChange
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Scrim (item 10): captures touches behind the panel so taps don't pass through to the
            // host app. Tapping the scrim closes the panel. Only present while open AND chrome is
            // shown — a hidden inbox hides all chrome, including an open panel/scrim.
            if isPanelOpen, showsChrome {
                // Scrim opacity 0.32 for cross-platform parity (Android uses the same value).
                Color.black.opacity(0.32)
                    .ignoresSafeAreaCompat()
                    .contentShape(Rectangle())
                    .onTapGesture { setPanel(open: false) }
                    .transition(.opacity)
            }

            // The slide-out panel sits above the scrim but behind the floating button.
            if isPanelOpen, showsChrome {
                panel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Bell is shown unless the inbox is hidden (item 11: hidden → no chrome).
            if showsChrome {
                floatingButton
            }
        }
        // Fill the host so bottom-trailing alignment pins the button to the bottom-right corner.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        // If the inbox transitions to hidden while the panel is open, close it so it doesn't linger
        // (and doesn't silently reappear if the inbox becomes visible again).
        .onChange(of: showsChrome) { visible in
            if !visible, isPanelOpen { isPanelOpen = false }
            // Re-notify when chrome visibility flips: if the inbox goes hidden while the panel flag is
            // still settling, the host must stop full-screen capture so touches aren't swallowed with
            // nothing on screen.
            notifyPanelPresentation()
        }
        // Notify the host of panel presentation so a passthrough-window mount can toggle full-screen
        // touch capture (presented → scrim blocks click-through; not → pass through).
        .onChange(of: isPanelOpen) { _ in
            notifyPanelPresentation()
        }
    }

    /// The panel is "presented" (host should capture full-screen touches) only when it is open AND the
    /// inbox chrome is shown. Keying the host callback off BOTH prevents leaving touch capture on after
    /// the inbox goes `.hidden` while `isPanelOpen` is still true.
    private func notifyPanelPresentation() {
        onPanelPresentationChange?(isPanelOpen && showsChrome)
    }

    // MARK: - Derived UI state

    /// Whether any chrome (bell/panel) should be shown. Hidden state shows nothing.
    private var showsChrome: Bool {
        switch model.state {
        case .hidden:
            return false
        case .idle, .loading:
            return true
        case .visible:
            // Visible but every message lacks a Jist template → nothing can render (each is logged +
            // skipped by the model). Show no chrome rather than a bell over a blank/“caught up” panel;
            // it reappears if a renderable message arrives.
            return !model.renderableMessages.isEmpty
        }
    }

    private func setPanel(open: Bool) {
        withAnimation(.easeInOut(duration: 0.3)) {
            isPanelOpen = open
        }
        // Auto-mark-opened (item 8): when the panel becomes visible, mark the visible messages
        // opened (deduped inside the model so a message is never marked twice).
        if open {
            model.markVisibleMessagesOpened()
        }
    }

    // MARK: - Floating button + badge (item 6)

    private var floatingButton: some View {
        Button(action: { setPanel(open: !isPanelOpen) }, label: {
            ZStack(alignment: .topTrailing) {
                // Default bundled SF Symbol bell (branding SVG bell is deferred).
                Image(systemName: "bell.fill")
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.accentColor)
                    .clipShape(Circle())
                    .shadow(radius: 4)

                if model.unopenedCount > 0 {
                    Text("\(model.unopenedCount)")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(5)
                        .background(Color.red)
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                }
            }
        })
        .padding(16)
        // `.accessibility(label:)` is the iOS 13-safe form; `.accessibilityLabel` is iOS 14+.
        .accessibility(label: Text(model.unopenedCount > 0 ? "Notifications, \(model.unopenedCount) unread" : "Notifications"))
    }

    // MARK: - Slide-out panel (items 6, 7, 11)

    private var panel: some View {
        // No header (title / close button) — matches web. The panel closes via the scrim tap or by
        // tapping the bell again.
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: 480, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 8)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, panelBottomInset)
    }

    /// Panel body driven by load state (item 11): spinner while loading, empty placeholder when
    /// visible-but-empty, otherwise the Jist-rendered list.
    @ViewBuilder
    private var content: some View {
        if model.messages.isEmpty, case .visible = model.state {
            // Genuinely caught up: visible with NO messages at all. Keyed off the full message list
            // (not `renderableMessages`) so messages that merely lack a template don't read as
            // "caught up" — those still exist, they just can't render.
            VStack {
                Spacer()
                Text("You're all caught up")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.messages.isEmpty {
            // idle/loading (pre-first-snapshot or fetch in progress) → spinner, not the empty copy.
            VStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Messages exist → render the renderable ones. If every message lacks a template the list
            // is blank (each is logged + skipped); we deliberately do NOT claim "caught up" here.
            messageList
        }
    }

    private var messageList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // No-template messages are skipped (item 4): `renderableMessages` drops any message
                // whose `type` has no matching decoded template (logged once by the model).
                ForEach(model.renderableMessages) { message in
                    VisualInboxMessageRow(
                        message: message,
                        data: model.decodedData[message.id] ?? [:],
                        templates: model.templates,
                        theme: model.theme,
                        // Web parity (item 1): tapping a message dismisses it. The row resolves the
                        // Jist action to a dismiss and calls back here; the model removes it.
                        onDismiss: { model.dismiss(messageId: message.id) },
                        // Non-dismiss actions (items 12/13): the row resolves the Jist action; the
                        // overlay tracks the click + offers it to the host, then runs default nav.
                        onAction: { resolution in handleNonDismissAction(messageId: message.id, resolution: resolution) }
                    )
                    Divider()
                }
            }
        }
    }

    // MARK: - Non-dismiss action handling (items 12 + 13)

    /// Tracks the click + offers the action to the host listener (via the model/data layer), then runs
    /// the SDK default navigation only if the host did NOT handle it.
    ///
    /// Default navigation (item 12):
    ///  - `openUrl` / `newTab` / a plain http(s) url → open the url via `UIApplication.shared.open`.
    ///  - `deeplink` → handed to the host; if there's no host listener (or it deferred) we log, since
    ///    the SDK can't know the host's in-app routing. We never force-unwrap a url.
    private func handleNonDismissAction(messageId: String, resolution: InboxActionResolution) {
        Task {
            let handledByHost = await model.handleAction(
                messageId: messageId,
                actionName: resolution.actionName,
                actionValue: resolution.url ?? ""
            )
            guard !handledByHost else { return }
            performDefaultNavigation(resolution)
        }
    }

    /// The SDK's default navigation for an un-intercepted, non-dismiss action. Robust to a missing or
    /// malformed url — no force-unwrap, no crash.
    private func performDefaultNavigation(_ resolution: InboxActionResolution) {
        let logger = DIGraphShared.shared.logger
        switch resolution.behavior {
        case .deeplink:
            // Deep links require host routing; with no host handler we can only log.
            logger.debug("[CIO-Inbox] deeplink action not handled by host: \(resolution.url ?? "<none>")")
        case .openUrl, .newTab, .none:
            guard let urlString = resolution.url, let url = URL(string: urlString) else {
                logger.debug("[CIO-Inbox] action has no openable url (name=\(resolution.actionName))")
                return
            }
            guard url.scheme == "http" || url.scheme == "https" else {
                // A non-web url with no explicit deeplink behavior — let the host decide; log only.
                logger.debug("[CIO-Inbox] action url is not http(s) and was not host-handled: \(urlString)")
                return
            }
            UIApplication.shared.open(url)
        }
    }
}

/// Cross-version `ignoresSafeArea` helper (the modern modifier is iOS 14+; `edgesIgnoringSafeArea`
/// covers iOS 13).
@available(iOS 13.0, *)
private extension View {
    @ViewBuilder
    func ignoresSafeAreaCompat() -> some View {
        if #available(iOS 14.0, *) {
            ignoresSafeArea()
        } else {
            edgesIgnoringSafeArea(.all)
        }
    }
}

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
        return InboxActionResolution(actionName: event.name, url: url, behavior: behavior)
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
