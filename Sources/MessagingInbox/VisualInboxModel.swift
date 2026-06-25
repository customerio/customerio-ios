import CioInternalCommon
@_spi(VisualInbox) import CioMessagingInApp
import Foundation
#if canImport(SwiftUI)
import Jist
import SwiftUI

/// Observable state holder that drives ``NotificationInboxOverlay``.
///
/// All SDK interaction goes through the `@_spi(VisualInbox)` ``VisualInboxProvider`` facade (the
/// overlay never touches the headless public `NotificationInbox` API). The model owns:
///  - the published render state (``VisualInboxState``) for loading/visible/hidden chrome (item 11),
///  - the selected messages + unopened count read-only API (item 9), and
///  - the auto-mark-opened dedupe guard (item 8).
///
/// Thread safety: `@MainActor` so all `@Published` mutations happen on the main thread; the
/// provider calls are `async` and hop back to the main actor before publishing.
@available(iOS 13.0, *)
@MainActor
final class VisualInboxModel: ObservableObject {
    /// Current visibility/loading state from the data layer. Drives which chrome is shown.
    @Published private(set) var state: VisualInboxState = .idle

    /// Selected/sorted messages to render. Read-only to the view (item 9).
    @Published private(set) var messages: [VisualInboxMessageSnapshot] = []

    /// Number of unopened messages — drives the unread badge (item 9).
    @Published private(set) var unopenedCount: Int = 0

    /// Templates registry decoded into Jist types, refreshed alongside `messages`. Decoded once per
    /// refresh (not per row) so the Jist render path stays cheap.
    @Published private(set) var templates: [String: [JistTemplate]] = [:]

    /// Branding theme decoded into Jist types, refreshed alongside `messages`.
    @Published private(set) var theme: [String: JistValue] = [:]

    /// Backend-branding chrome colors (bell / panel / badge / divider, parsed from `patterns.inbox`
    /// plus optional dark-mode overrides). Drives the overlay's chrome instead of hardcoded colors;
    /// nil until the first load, and nil-per-field when a workspace hasn't configured inbox branding.
    /// Branding is stable per session, so it's fetched on `refresh()` (not per `observe()` emission).
    @Published private(set) var chrome: VisualInboxChrome?

    /// Each message's `properties` decoded into Jist render data, keyed by message id. Decoded ONCE
    /// per `messages` refresh (here, not per render) so the row body just reads the prepared value
    /// instead of re-decoding `[String: Any]` on every recompose.
    @Published private(set) var decodedData: [String: [String: JistValue]] = [:]

    private let provider: VisualInboxProvider

    /// SDK logger for [CIO-Inbox] diagnostics (e.g. the no-template skip in item 4).
    private let logger: Logger = DIGraphShared.shared.logger

    /// Ids already logged as "no matching template" so the skip warning is emitted once per message
    /// rather than on every refresh/recompose.
    private var loggedMissingTemplateIds: Set<String> = []

    /// Messages that have a matching decoded template and are therefore renderable via Jist.
    ///
    /// No-template fallback (item 4): a message whose `type` is not in the decoded templates registry
    /// is skipped (not rendered as a blank row) and logged once as a [CIO-Inbox] error. We can't skip
    /// in pre-iOS-15 fallback rows (no templates there), so the skip only applies when Jist renders.
    var renderableMessages: [VisualInboxMessageSnapshot] {
        guard #available(iOS 15.0, *) else { return messages }
        return messages.filter { templates[$0.type] != nil }
    }

    /// Whether any inbox chrome (bell/panel) should be shown. Hidden state shows nothing (item 11).
    /// Shared by the bell, panel, and overlay so all three react identically to a visibility flip.
    var showsChrome: Bool {
        switch state {
        case .hidden: return false
        case .idle, .loading, .visible: return true
        }
    }

    /// Backing task for the load + refresh cycle; cancelled when the view disappears.
    private var refreshTask: Task<Void, Never>?

    /// Backing task for the continuous `observe()` subscription; cancelled when the view disappears.
    /// This is what makes the overlay REACTIVE: it republishes whenever the data layer's
    /// enablement/visibility/messages/opened-state change, with no recompose or navigation.
    private var observeTask: Task<Void, Never>?

    /// In-flight branding-chrome load; cancel-and-replaced by `reloadChrome()` so emissions don't stack.
    private var chromeLoadTask: Task<Void, Never>?

    /// In-flight / already-done guard for auto-mark-opened (item 8). A message id present here has
    /// either been marked or is being marked, so it is never marked twice.
    private var markedOpenedIds: Set<String> = []

    /// In-flight guard for dismiss (web parity: tap → dismiss). A message id present here has a
    /// dismiss in flight, so a rapid double-tap / re-entrant `onAction` can't double-fire the delete.
    private var dismissingIds: Set<String> = []

    /// Ids already reported as "shown" so we dispatch the host-callback Task at most once per message
    /// (the data layer dedupes too, but this avoids spawning a Task on every recompose).
    private var shownMessageIds: Set<String> = []

    init(provider: VisualInboxProvider) {
        self.provider = provider
    }

    /// Convenience initializer using the shared DI graph's Visual Inbox provider.
    convenience init() {
        self.init(provider: DIGraphShared.shared.visualInboxProvider)
    }

    deinit {
        refreshTask?.cancel()
        observeTask?.cancel()
        chromeLoadTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Kicks off the data-layer load AND subscribes to the continuous `observe()` stream so the
    /// overlay stays reactive. Safe to call repeatedly; an in-flight load/subscription is reused.
    ///
    /// The one-shot `load()` still runs (it triggers the fetch-if-missing on the data layer and gives
    /// an immediate first paint), but continuous updates are driven by the subscription below — so
    /// when enablement flips true ~3s after launch (or messages / opened-state change), the published
    /// state updates automatically and the bell appears with no recompose.
    func start() {
        if refreshTask == nil {
            refreshTask = Task { [weak self] in
                guard let self = self else { return }
                await self.provider.load()
                if Task.isCancelled { return }
                await self.refresh()
            }
        }
        if observeTask == nil {
            observeTask = Task { [weak self] in
                guard let self = self else { return }
                for await snapshot in self.provider.observe() {
                    if Task.isCancelled { return }
                    self.apply(snapshot: snapshot)
                }
            }
        }
    }

    /// Cancels the load/refresh cycle and the continuous subscription.
    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        observeTask?.cancel()
        observeTask = nil
        chromeLoadTask?.cancel()
        chromeLoadTask = nil
    }

    /// Pulls the latest state + messages + unopened count from the data layer onto the main actor.
    /// Retained for the one-shot path (initial paint / after mark-opened); continuous updates come
    /// through `apply(snapshot:)` via the `observe()` subscription.
    func refresh() async {
        let newState = await provider.state()
        let newMessages = await provider.messages()
        // Derive the badge from the same messages array (rather than a separate provider read) so the
        // count can never disagree with the list if the store changes mid-refresh.
        let newUnopened = newMessages.filter { !$0.opened }.count
        let newTemplates = VisualInboxJistDecoder.decodeTemplates(await provider.templatesJSON())
        let newTheme = VisualInboxJistDecoder.decodeTheme(await provider.themeJSON())
        if Task.isCancelled { return }
        state = newState
        messages = newMessages
        unopenedCount = newUnopened
        templates = newTemplates
        theme = newTheme
        decodedData = Self.decodeData(for: newMessages)
        logMissingTemplates()
        // Chrome is loaded off this synchronous state-publish path (a chrome await here would widen a
        // window where a late resume overwrites newer observe() state, e.g. unopenedCount).
        reloadChrome()
    }

    /// Publishes a coalesced snapshot from the `observe()` stream. Runs on the main actor (the model
    /// is `@MainActor`), so the SwiftUI view re-renders automatically.
    func apply(snapshot: VisualInboxSnapshot) {
        state = snapshot.state
        messages = snapshot.messages
        unopenedCount = snapshot.unopenedCount
        templates = VisualInboxJistDecoder.decodeTemplates(snapshot.templatesJSON)
        theme = VisualInboxJistDecoder.decodeTheme(snapshot.themeJSON)
        decodedData = Self.decodeData(for: snapshot.messages)
        logMissingTemplates()
        reloadChrome()
    }

    /// (Re)loads the branding chrome off the synchronous state-publish path.
    ///
    /// Loaded here rather than inline in `refresh()`/`apply()` because an extra await there can let a
    /// late resume clobber newer observe() state. Unlike the message `theme`, branding chrome can also
    /// change when the branding cache updates, so this is NOT a load-once: it re-reads on each refresh
    /// so bell/panel/badge colors track branding. Coalesced via a single cancel-and-replace task so
    /// frequent `observe()` emissions can't stack redundant in-flight loads. Mutates `@Published
    /// chrome` on the main actor.
    private func reloadChrome() {
        chromeLoadTask?.cancel()
        chromeLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let resolved = await self.provider.brandingChrome()
            if Task.isCancelled { return }
            if let resolved { self.chrome = resolved }
        }
    }

    /// Emits a one-time [CIO-Inbox] error for each message whose `type` has no matching decoded
    /// template (item 4). These messages are skipped by `renderableMessages` so they never render as
    /// a blank row. Logged once per id to avoid per-refresh spam.
    private func logMissingTemplates() {
        guard #available(iOS 15.0, *) else { return }
        for message in messages where templates[message.type] == nil && !loggedMissingTemplateIds.contains(message.id) {
            loggedMissingTemplateIds.insert(message.id)
            logger.error("[CIO-Inbox] skipping message \(message.id): no template for type \"\(message.type)\" in registry")
        }
    }

    /// Decodes each message's `properties` into Jist render data once, keyed by message id.
    private static func decodeData(for messages: [VisualInboxMessageSnapshot]) -> [String: [String: JistValue]] {
        var result: [String: [String: JistValue]] = [:]
        for message in messages {
            result[message.id] = VisualInboxJistDecoder.decodeData(message.properties)
        }
        return result
    }

    // MARK: - Auto mark-opened (item 8)

    /// Marks every currently-visible message opened, exactly once each. Called when the panel opens
    /// (and re-callable as new messages scroll into view). The `markedOpenedIds` guard dedupes so a
    /// message is never marked repeatedly across panel open/close cycles or refreshes.
    func markVisibleMessagesOpened() {
        // Only mark messages the user can actually see: `renderableMessages` (those with a template).
        // Messages skipped for a missing template are never shown in the list, so they must not be
        // marked opened.
        let toMark = renderableMessages.filter { !$0.opened && !markedOpenedIds.contains($0.id) }
        guard !toMark.isEmpty else { return }
        // Reserve ids synchronously (on the main actor) so a re-entrant call can't double-fire the
        // same mark while the async marks are in flight.
        for message in toMark {
            markedOpenedIds.insert(message.id)
        }
        Task { [weak self, provider] in
            for message in toMark {
                // If the message has since left the store the mark no-ops (returns false). Release
                // the reservation in that case so the id stays RETRYABLE instead of being deduped
                // forever on a mark that never applied. A mark that did apply stays reserved.
                let didMark = await provider.markOpened(messageId: message.id)
                if !didMark {
                    self?.markedOpenedIds.remove(message.id)
                }
            }
            await self?.refresh()
        }
    }

    // MARK: - Dismiss (web parity: tap → dismiss)

    /// Dismisses (removes) a message, mirroring web behavior where tapping a message removes it from
    /// the list. Dismissing the last message empties the list, which drives the data layer to
    /// `.hidden` — the panel auto-closes and the bell hides (item 2).
    ///
    /// The `dismissingIds` guard dedupes so a rapid double-tap / re-entrant `onAction` for the same
    /// message can't dispatch the delete twice. If the dismiss no-ops (message already gone) the
    /// reservation is released so the id stays retryable.
    func dismiss(messageId: String) {
        guard !dismissingIds.contains(messageId) else { return }
        dismissingIds.insert(messageId)
        Task { [weak self, provider] in
            let didDismiss = await provider.dismiss(messageId: messageId)
            if !didDismiss {
                self?.dismissingIds.remove(messageId)
            }
            await self?.refresh()
        }
    }

    // MARK: - Non-dismiss actions (items 12 + 13)

    /// Routes a NON-dismiss inbox action through the data layer (track click + host listener) and
    /// reports the outcome. Awaited by the row so the overlay runs its default navigation only when
    /// the action was tracked but un-handled (not when the host handled it or the message is gone).
    func handleAction(messageId: String, actionName: String, actionValue: String) async -> VisualInboxActionOutcome {
        await provider.handleMessageAction(messageId: messageId, actionName: actionName, actionValue: actionValue)
    }

    // MARK: - Shown (observe-only host callback)

    /// Reports that a message has been rendered (shown) in the visible inbox so the data layer can
    /// fire the host `inboxMessageShown` callback. Deduped both here (so we don't dispatch a Task per
    /// recompose) and in the data layer (so the host fires at most once per message per session).
    func markShown(messageId: String) {
        guard !shownMessageIds.contains(messageId) else { return }
        shownMessageIds.insert(messageId)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let didNotify = await self.provider.notifyMessageShown(messageId: messageId)
            // If the message had already left the store the notify no-ops; release the reservation so
            // a later render can retry (mirrors markVisibleMessagesOpened's failed-mark handling).
            if !didNotify { self.shownMessageIds.remove(messageId) }
        }
    }
}
#endif
