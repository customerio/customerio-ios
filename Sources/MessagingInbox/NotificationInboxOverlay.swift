import CioInternalCommon
@_spi(VisualInbox) import CioMessagingInApp
import Foundation
#if canImport(SwiftUI)
import Jist
import SwiftUI

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

    /// Creates an inbox overlay backed by the SDK's shared Visual Inbox data layer.
    public init() {
        _model = StateObject(wrappedValue: VisualInboxModel())
    }

    /// Creates an inbox overlay backed by the supplied model. Used by tests/previews to inject a fake.
    init(model: VisualInboxModel) {
        _model = StateObject(wrappedValue: model)
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Scrim (item 10): captures touches behind the panel so taps don't pass through to the
            // host app. Tapping the scrim closes the panel. Only present while open AND chrome is
            // shown — a hidden inbox hides all chrome, including an open panel/scrim.
            if isPanelOpen, showsChrome {
                Color.black.opacity(0.2)
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
        }
    }

    // MARK: - Derived UI state

    /// Whether any chrome (bell/panel) should be shown. Hidden state shows nothing.
    private var showsChrome: Bool {
        switch model.state {
        case .hidden: return false
        case .idle, .loading, .visible: return true
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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Inbox")
                    .font(.headline)

                Spacer()

                Button(action: { setPanel(open: false) }, label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                })
                .accessibility(label: Text("Close inbox"))
            }
            .padding()

            Divider()

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
            // Visible with no messages → genuine "caught up" empty state.
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
            messageList
        }
    }

    private var messageList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.messages) { message in
                    VisualInboxMessageRow(
                        message: message,
                        data: model.decodedData[message.id] ?? [:],
                        templates: model.templates,
                        theme: model.theme
                    )
                    Divider()
                }
            }
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

    var body: some View {
        Group {
            if #available(iOS 15.0, *) {
                JistView(
                    name: message.type,
                    templates: templates,
                    data: data,
                    theme: theme,
                    mode: .auto,
                    formatDate: nil,
                    // swiftlint:disable:next todo
                    // TODO: action mapping is deferred (scope items 12/13). For now actions are a
                    // no-op hook — wire to trackMessageClicked / deep-link handling later.
                    onAction: { _ in }
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
}
#endif
