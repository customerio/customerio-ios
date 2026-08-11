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
public struct NotificationInboxView: View {
    /// Owns the model for standalone embedding. `@State` intentionally preserves the existing
    /// ownership behavior; `@ObservedObject` would not own the value and could replace a started
    /// model during parent updates, losing load state, dedupe guards, and in-flight work. Moving to
    /// another ownership wrapper requires separate lifecycle validation.
    @State private var model = VisualInboxModel()

    /// Creates a standalone inbox list backed by the SDK's shared Visual Inbox data layer.
    public init() {}

    public var body: some View {
        InboxListView(model: model, ownsModelLifecycle: true, marksOpenedOnAppear: true)
    }
}

/// Renders the inbox list for a model it does not own. Always constructed with an explicit model —
/// either the shared one from ``NotificationInboxOverlay`` or the one ``NotificationInboxView`` owns.
struct InboxListView: View {
    @ObservedObject private var model: VisualInboxModel

    /// A view may stay mounted while hidden under another tab or navigation destination, so
    /// notification subscription lifetime alone cannot establish visual presence.
    @State private var isOnScreen = false

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

    /// Performs the SDK default navigation for an un-intercepted action. Injected (constructor DI)
    /// rather than reaching into `DIGraphShared.shared` inline, so navigation is testable.
    private let navigator: InboxActionNavigating

    /// Creates a list observing a shared model (used by ``NotificationInboxOverlay`` so the bell,
    /// panel, and overlay all observe the same state). The overlay drives lifecycle + mark-opened and
    /// passes `onNavigate` to close its sheet after a navigation action.
    init(
        model: VisualInboxModel,
        ownsModelLifecycle: Bool = false,
        marksOpenedOnAppear: Bool = false,
        onNavigate: (() -> Void)? = nil,
        navigator: InboxActionNavigating = DefaultInboxActionNavigator()
    ) {
        _model = ObservedObject(wrappedValue: model)
        self.ownsModelLifecycle = ownsModelLifecycle
        self.marksOpenedOnAppear = marksOpenedOnAppear
        self.onNavigate = onNavigate
        self.navigator = navigator
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .modifier(LifecycleModifier(model: model, enabled: ownsModelLifecycle))
            .onAppear {
                isOnScreen = true
                updateAutoMarkState()
            }
            .onDisappear {
                isOnScreen = false
                if marksOpenedOnAppear { model.setAutoMarkVisibleMessagesOpened(false) }
            }
            // A mounted SwiftUI view does not disappear when its app backgrounds. Explicitly gate
            // auto-marking on application activity so background snapshots never become "opened".
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                if marksOpenedOnAppear { model.setAutoMarkVisibleMessagesOpened(false) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                updateAutoMarkState()
            }
    }

    /// Reconciles standalone auto-mark behavior with actual visual and application activity.
    private func updateAutoMarkState() {
        // The overlay drives this state itself; its shared list must never override the owner.
        guard marksOpenedOnAppear else { return }
        model.setAutoMarkVisibleMessagesOpened(
            VisualInboxModel.shouldAutoMarkVisibleMessagesOpened(
                isPresented: true,
                isOnScreen: isOnScreen,
                isApplicationActive: UIApplication.shared.applicationState == .active
            )
        )
    }

    /// Panel body driven by load state: nothing when the inbox is hidden, spinner while loading,
    /// empty placeholder when visible-but-empty, otherwise the Jist-rendered list.
    @ViewBuilder
    private var content: some View {
        if case .hidden = model.state {
            // Inbox is not renderable (disabled workspace, missing templates/branding). Render
            // nothing — matching the overlay, which hides its chrome entirely in this state —
            // rather than a perpetual spinner (empty + hidden) or a stale list (messages + hidden).
            EmptyView()
        } else if model.messages.isEmpty, case .visible = model.state {
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
                InboxLoadingSpinner()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            messageList
        }
    }

    /// Top inset above the first message row so it doesn't hug the sheet grabber (MBL-2122), matching
    /// the comfortable top margin of the web inbox. Single, easily-tunable value.
    private static let listTopInset: CGFloat = 16

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
            .padding(.top, Self.listTopInset)
        }
    }

    // MARK: - Non-dismiss action handling (items 12 + 13)

    /// Tracks the click + offers the action to the host listener (via the model/data layer), then runs
    /// the SDK default navigation only if the host did NOT handle it.
    ///
    /// Default navigation (item 12), mirroring web `handleInboxAction`:
    ///  - `openUrl` with a value → open it externally via `UIApplication.shared.open`.
    ///  - `openDeeplink` with a value → route through the SDK's shared deep-link handling
    ///    (`deepLinkUtil.handleDeepLink`), identical to push-notification and in-app-message deep links.
    ///  - `performAction` / `unknown` → no SDK navigation; the host was already offered the action.
    ///  We never force-unwrap a value.
    private func handleNonDismissAction(messageId: String, resolution: InboxActionResolution) {
        Task {
            let outcome = await model.handleAction(
                messageId: messageId,
                actionName: resolution.actionName,
                actionValue: resolution.actionValue ?? ""
            )
            // Resolve the navigating destination ONCE, up front: only `openUrl`/`openDeeplink` with a
            // value that actually parses to a `URL` navigates. Both the sheet dismiss AND the SDK
            // navigation gate on this, so a non-empty-but-unparseable value neither dismisses the inbox
            // nor drops it into a closed-but-unnavigated state.
            let navigationURL = navigationURL(for: resolution)
            // A navigating action routes away from the inbox — whether the SDK performs it OR the host
            // intercepted it — so close the sheet so the destination isn't left behind it.
            // `performAction` / `unknown` / auto-`dismiss`, a missing message, or an empty/invalid value
            // keep the inbox open. Dismiss FIRST, before the SDK enqueues navigation below, so the
            // sheet is already closing when the deep link is handled.
            if navigationURL != nil, outcome != .messageMissing {
                await MainActor.run { onNavigate?() }
            }
            switch outcome {
            case .handledByHost:
                // Host intercepted the action — suppress the SDK default navigation.
                break
            case .messageMissing:
                // Message gone from the store (tapped after removal): nothing tracked, don't navigate.
                DIGraphShared.shared.logger.debug("[CIO-Inbox] action on missing message \(messageId): skipping default navigation")
            case .notHandled:
                performDefaultNavigation(behavior: resolution.behavior, url: navigationURL, actionName: resolution.actionName)
            }
            // "Auto dismiss on click" (data.dismiss == true): remove the message after running its
            // action, regardless of host handling / navigation.
            if resolution.dismiss {
                model.dismiss(messageId: messageId)
            }
        }
    }

    /// The parsed navigation destination for a navigating action: `openUrl`/`openDeeplink` whose value
    /// is non-empty AND forms a `URL`. nil for every other behavior, or an empty/unparseable value.
    private func navigationURL(for resolution: InboxActionResolution) -> URL? {
        guard resolution.behavior == .openUrl || resolution.behavior == .openDeeplink,
              let value = resolution.actionValue, !value.isEmpty else { return nil }
        return URL(string: value)
    }

    /// The SDK's default navigation for an un-intercepted, non-dismiss action, using the URL resolved
    /// up front by ``navigationURL(for:)``. Robust to a missing/malformed url — no force-unwrap.
    private func performDefaultNavigation(behavior: InboxActionResolution.Behavior, url: URL?, actionName: String) {
        let logger = DIGraphShared.shared.logger
        switch behavior {
        case .openUrl:
            // Web parity: `openUrl` navigates to the value (external), via the injected navigator.
            guard let url else {
                logger.debug("[CIO-Inbox] openUrl action has no openable value (name=\(actionName))")
                return
            }
            navigator.openExternalURL(url)
        case .openDeeplink:
            // Route through the SDK's shared deep-link handling — host `deepLinkCallback` → universal-
            // link handoff → system open — identical to push-notification and in-app-message deep
            // links, so inbox deep links behave consistently with the rest of the SDK.
            guard let url else {
                logger.debug("[CIO-Inbox] openDeeplink action has no openable value (name=\(actionName))")
                return
            }
            navigator.handleDeepLink(url)
        case .performAction, .unknown:
            // No SDK navigation — the host was already offered the action via `messageActionTaken`
            // (web dispatches its `inboxMessageAction` event and does nothing else here).
            logger.debug("[CIO-Inbox] \(behavior) action: no default navigation (name=\(actionName))")
        }
    }
}

/// Preserves the standalone inbox list's existing medium UIKit loading indicator. Migrating to a
/// different SwiftUI loading view requires separate visual validation.
private struct InboxLoadingSpinner: UIViewRepresentable {
    func makeUIView(context: Context) -> UIActivityIndicatorView {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.startAnimating()
        return indicator
    }

    func updateUIView(_ uiView: UIActivityIndicatorView, context: Context) {}
}
#endif
