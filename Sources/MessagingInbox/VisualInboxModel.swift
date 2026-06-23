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

    /// Each message's `properties` decoded into Jist render data, keyed by message id. Decoded ONCE
    /// per `messages` refresh (here, not per render) so the row body just reads the prepared value
    /// instead of re-decoding `[String: Any]` on every recompose.
    @Published private(set) var decodedData: [String: [String: JistValue]] = [:]

    private let provider: VisualInboxProvider

    /// Backing task for the load + refresh cycle; cancelled when the view disappears.
    private var refreshTask: Task<Void, Never>?

    /// Backing task for the continuous `observe()` subscription; cancelled when the view disappears.
    /// This is what makes the overlay REACTIVE: it republishes whenever the data layer's
    /// enablement/visibility/messages/opened-state change, with no recompose or navigation.
    private var observeTask: Task<Void, Never>?

    /// In-flight / already-done guard for auto-mark-opened (item 8). A message id present here has
    /// either been marked or is being marked, so it is never marked twice.
    private var markedOpenedIds: Set<String> = []

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
        let toMark = messages.filter { !$0.opened && !markedOpenedIds.contains($0.id) }
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
}
#endif
