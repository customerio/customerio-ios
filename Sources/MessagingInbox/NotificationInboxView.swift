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

    /// Invoked after a navigation action (`openUrl`/`openDeeplink` with a destination) is handled, so
    /// the presenter can dismiss (the overlay closes its sheet so the opened screen isn't left behind
    /// it). nil for standalone embedding, where the host owns presentation.
    private let onNavigate: (() -> Void)?

    /// Creates a standalone inbox list backed by the SDK's shared Visual Inbox data layer.
    public init() {
        _model = ObservedObject(wrappedValue: VisualInboxModel())
        self.ownsModelLifecycle = true
        self.marksOpenedOnAppear = true
        self.onNavigate = nil
    }

    /// Creates a list observing a shared model (used by ``NotificationInboxOverlay`` so the bell,
    /// panel, and overlay all observe the same state). The overlay drives lifecycle + mark-opened and
    /// passes `onNavigate` to close its sheet after a navigation action.
    init(model: VisualInboxModel, onNavigate: (() -> Void)? = nil) {
        _model = ObservedObject(wrappedValue: model)
        self.ownsModelLifecycle = false
        self.marksOpenedOnAppear = false
        self.onNavigate = onNavigate
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
        if model.messages.isEmpty, case .visible = model.state {
            // Genuinely caught up: visible with NO messages at all. Keyed off the full message list
            // (not `renderableMessages`) so messages that merely lack a template don't read as
            // "caught up". (When embedded standalone; the overlay hides chrome entirely in that case.)
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
    /// Default navigation (item 12), mirroring web `handleInboxAction`:
    ///  - `openUrl` / `openDeeplink` with a value → open it via `UIApplication.shared.open` (routes
    ///    http(s) to the browser and a custom scheme to the registered/host app). `javascript:` is
    ///    blocked, matching web's `isSafeUrl`.
    ///  - `performAction` / `unknown` → no SDK navigation; the host was already offered the action.
    ///  We never force-unwrap a value.
    private func handleNonDismissAction(messageId: String, resolution: InboxActionResolution) {
        Task {
            let outcome = await model.handleAction(
                messageId: messageId,
                actionName: resolution.actionName,
                actionValue: resolution.actionValue ?? ""
            )
            switch outcome {
            case .handledByHost:
                // Host intercepted the action — suppress the SDK default navigation.
                break
            case .messageMissing:
                // Message gone from the store (tapped after removal): nothing tracked, don't navigate.
                DIGraphShared.shared.logger.debug("[CIO-Inbox] action on missing message \(messageId): skipping default navigation")
            case .notHandled:
                performDefaultNavigation(resolution)
            }
            // "Auto dismiss on click" (data.dismiss == true): remove the message after running its
            // action, regardless of host handling / navigation.
            if resolution.dismiss {
                model.dismiss(messageId: messageId)
            }
            // Close the inbox after a DEEP-LINK action so the opened in-app screen isn't left sitting
            // behind the inbox sheet. Only `openDeeplink` dismisses: it routes within/into the app, so
            // the sheet would otherwise cover the destination. `openUrl` opens externally (browser) and
            // leaves nothing behind the sheet; `performAction`/`dismiss` keep the inbox open. Fires
            // whether the SDK opened it or the host handled it; skipped for a missing message or an
            // empty destination.
            let isDeeplinkNavigation = resolution.behavior == .openDeeplink
            if isDeeplinkNavigation, outcome != .messageMissing, resolution.actionValue?.isEmpty == false {
                await MainActor.run { onNavigate?() }
            }
        }
    }

    /// The SDK's default navigation for an un-intercepted, non-dismiss action. Robust to a missing or
    /// malformed url — no force-unwrap, no crash.
    private func performDefaultNavigation(_ resolution: InboxActionResolution) {
        let logger = DIGraphShared.shared.logger
        switch resolution.behavior {
        case .openUrl:
            // Web parity: `openUrl` navigates to the value (external). Mirror the in-app message page
            // action and open via the system. Runs on the main actor (UIKit API) after the model await.
            guard let value = resolution.actionValue, let url = URL(string: value) else {
                logger.debug("[CIO-Inbox] openUrl action has no openable value (name=\(resolution.actionName))")
                return
            }
            DispatchQueue.main.async { UIApplication.shared.open(url) }
        case .openDeeplink:
            // Route through the SDK's shared deep-link handling — host `deepLinkCallback` → universal-
            // link handoff → system open — identical to push-notification and in-app-message deep
            // links, so inbox deep links behave consistently with the rest of the SDK.
            guard let value = resolution.actionValue, let url = URL(string: value) else {
                logger.debug("[CIO-Inbox] openDeeplink action has no openable value (name=\(resolution.actionName))")
                return
            }
            DispatchQueue.main.async { DIGraphShared.shared.deepLinkUtil.handleDeepLink(url) }
        case .performAction, .unknown:
            // No SDK navigation — the host was already offered the action via `messageActionTaken`
            // (web dispatches its `inboxMessageAction` event and does nothing else here).
            logger.debug("[CIO-Inbox] \(resolution.behavior) action: no default navigation (name=\(resolution.actionName))")
        }
    }
}
#endif
