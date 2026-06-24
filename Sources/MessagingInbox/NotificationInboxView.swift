import CioInternalCommon
@_spi(VisualInbox) import CioMessagingInApp
import Foundation
#if canImport(SwiftUI)
import Jist
import SwiftUI
import UIKit

/// The Visual Notification Inbox message list, WITHOUT the floating bell / slide-out / scrim chrome.
///
/// Embed it directly in a host screen (a sheet, a tab, a dedicated inbox screen) to render the
/// inbox's messages natively via **Jist** from the server-provided templates + branding theme. It
/// shows a loading spinner while fetching, an empty "all caught up" state when there are no messages,
/// and the rendered list otherwise.
///
/// Behavior preserved from ``NotificationInboxOverlay``: tap-to-dismiss (web parity), relative dates,
/// no-template skip, host action callback + default navigation, mark-opened, and shown reporting.
///
/// ## Usage
/// ```swift
/// NavigationView { NotificationInboxView() }
/// ```
@available(iOS 13.0, *)
public struct NotificationInboxView: View {
    @ObservedObject private var model: VisualInboxModel

    /// Drives dark-mode branding resolution for the row divider.
    @Environment(\.colorScheme) private var colorScheme

    /// True when this view owns the model's lifecycle (standalone use) vs. observing a shared model
    /// owned by ``NotificationInboxOverlay``.
    private let ownsModelLifecycle: Bool

    /// When true (standalone embedding), the view marks its visible messages opened on appear — there
    /// is no panel-open event to drive it. ``NotificationInboxOverlay`` sets this `false` and marks on
    /// panel open instead.
    private let marksOpenedOnAppear: Bool

    /// Creates a standalone inbox list backed by the SDK's shared Visual Inbox data layer.
    public init() {
        _model = ObservedObject(wrappedValue: VisualInboxModel())
        self.ownsModelLifecycle = true
        self.marksOpenedOnAppear = true
    }

    /// Creates a list observing a shared model (used by ``NotificationInboxOverlay`` so the bell,
    /// panel, and overlay all observe the same state). The overlay drives lifecycle + mark-opened.
    init(model: VisualInboxModel) {
        _model = ObservedObject(wrappedValue: model)
        self.ownsModelLifecycle = false
        self.marksOpenedOnAppear = false
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .modifier(LifecycleModifier(model: model, enabled: ownsModelLifecycle))
            .onAppear { if marksOpenedOnAppear { model.markVisibleMessagesOpened() } }
    }

    /// Panel body driven by load state: spinner while loading, empty placeholder when visible-but-empty,
    /// otherwise the Jist-rendered list.
    @ViewBuilder
    private var content: some View {
        if model.renderableMessages.isEmpty, case .visible = model.state {
            // Visible with no messages → genuine "caught up" empty state.
            VStack {
                Spacer()
                Text("You're all caught up")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.renderableMessages.isEmpty {
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
        // Branding-first row divider (falls back to the system separator color).
        let colors = ResolvedInboxColors.resolve(chrome: model.chrome, isDark: colorScheme == .dark)
        return ScrollView {
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
                        // view tracks the click + offers it to the host, then runs default nav.
                        onAction: { resolution in handleNonDismissAction(messageId: message.id, resolution: resolution) }
                    )
                    // Shown (item 13): a message is reported once when it first renders here (deduped
                    // in the model + data layer so it fires at most once per message per session).
                    .onAppear { model.markShown(messageId: message.id) }
                    colors.divider.frame(height: 1)
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
            let outcome = await model.handleAction(
                messageId: messageId,
                actionName: resolution.actionName,
                actionValue: resolution.url ?? ""
            )
            switch outcome {
            case .handledByHost:
                // Host intercepted the action — suppress the SDK default navigation.
                return
            case .messageMissing:
                // Message gone from the store (tapped after removal): nothing tracked, don't navigate.
                DIGraphShared.shared.logger.debug("[CIO-Inbox] action on missing message \(messageId): skipping default navigation")
                return
            case .notHandled:
                performDefaultNavigation(resolution)
            }
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
            // `performDefaultNavigation` runs inside an unstructured Task (after awaiting the
            // main-actor model), so hop back to the main actor: UIApplication.shared.open is a
            // UIKit/main-thread API.
            DispatchQueue.main.async { UIApplication.shared.open(url) }
        }
    }
}
#endif
