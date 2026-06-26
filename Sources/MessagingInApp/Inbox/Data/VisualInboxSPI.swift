import CioInternalCommon
import Foundation

// MARK: - Visual Inbox cross-module SPI

// The ONLY bridge the Visual Inbox overlay UI module (`CioMessagingInbox`) uses to reach the in-app
// data layer. It is gated behind `@_spi(VisualInbox)` so it stays off the public SDK surface (only a
// sibling module that writes `@_spi(VisualInbox) import CioMessagingInApp` can see it). The internal
// data-layer types stay `internal`; this layer exposes plain Foundation value types instead, leaving
// the headless public `NotificationInbox` API untouched. The SPI value types
// (`VisualInboxState`/`VisualInboxMessageSnapshot`/`VisualInboxSnapshot`) live in
// `VisualInboxSPITypes.swift`.

/// Read-facing cross-module facade over the Visual Inbox data layer.
///
/// All accessors are `async` because the backing repository is an `actor`. The overlay observes
/// state, reads the rendering inputs (messages + raw templates/theme JSON), and triggers
/// mark-opened — but it never re-implements any data-layer policy.
@_spi(VisualInbox)
public protocol VisualInboxProvider: Sendable {
    /// A continuous stream of coalesced overlay snapshots. Emits on subscribe (current state) and
    /// then on every relevant data-layer change: the inbox enablement/visibility flip (via the
    /// repository load-state stream) and inbox message-set / opened-state changes (via the in-app
    /// store subscription). Emissions are de-duped, and reading a snapshot only reads cached state —
    /// it never triggers a network fetch.
    func observe() -> AsyncStream<VisualInboxSnapshot>
    /// Ensures the data layer has fetched templates + branding (idempotent / fetch-if-missing),
    /// transitioning `state` through `.loading` to a terminal `.visible`/`.hidden`.
    func load() async

    /// Current visibility/loading state.
    func state() async -> VisualInboxState

    /// Selected/sorted visual-inbox messages (cio_inbox prefix, priority/sentAt, expiry-dropped).
    func messages() async -> [VisualInboxMessageSnapshot]

    /// Count of selected messages the user has not yet opened — drives the unread badge.
    func unopenedCount() async -> Int

    /// Raw templates registry JSON (`{ name: [versions] }`), or nil if unavailable. The overlay
    /// decodes this into Jist `[String: [JistTemplate]]`.
    func templatesJSON() async -> [String: Any]?

    /// Raw branding theme tokens JSON, or nil if unavailable. The overlay decodes this into Jist
    /// `[String: JistValue]`.
    func themeJSON() async -> [String: Any]?

    /// Inbox chrome colors (bell / panel / badge / divider) parsed from `patterns.inbox`, plus the
    /// optional `patterns.modes.dark` overrides, so the overlay drives its chrome from backend
    /// branding. Nil when no branding is cached; individual fields are nil when not configured.
    func brandingChrome() async -> VisualInboxChrome?

    /// Marks a message opened via the existing headless plumbing (no new mutation path). Looked up
    /// by the snapshot id so the overlay never has to hold an internal `InboxMessage`.
    /// - Returns: `true` if a matching message was still present in the store and the mark was
    ///   issued; `false` if the message was gone (the mark was a no-op). Callers use this to avoid
    ///   permanently deduping a mark that never applied.
    @discardableResult
    func markOpened(messageId: String) async -> Bool

    /// Dismisses (removes) a message via the existing headless `markMessageDeleted` plumbing (no new
    /// mutation path). Looked up by the snapshot id so the overlay never has to hold an internal
    /// `InboxMessage`. Web parity: tapping a message dismisses it; dismissing the last message empties
    /// the list and drives the inbox to `.hidden` (panel auto-closes, bell hides).
    /// - Returns: `true` if a matching message was still present in the store and the delete was
    ///   issued; `false` if the message was gone (the dismiss was a no-op). Callers use this to avoid
    ///   permanently deduping a dismiss that never applied.
    @discardableResult
    func dismiss(messageId: String) async -> Bool

    /// Handles a NON-dismiss inbox action (item 12 / item 13). Resolves the full message by id, then:
    ///  - tracks a "clicked" metric via the existing headless `trackMessageClicked` plumbing (no new
    ///    network path), and
    ///  - forwards the action to the registered host ``InboxEventListener``.
    ///
    /// Dismiss is NOT routed here — the overlay handles dismiss before calling this.
    /// - Returns: a ``VisualInboxActionOutcome`` distinguishing a missing message (skip default nav)
    ///   from a host-handled action (suppress nav) and an un-handled action (run default nav).
    func handleMessageAction(messageId: String, actionName: String, actionValue: String) async -> VisualInboxActionOutcome

    /// Notifies the host ``InboxEventListener`` that a message was first shown (rendered in the visible
    /// inbox). Resolved by id from the store and forwarded via the existing headless plumbing, which
    /// dedupes so it fires at most once per message per session.
    /// - Returns: `true` if the message was still in the store (notify forwarded); `false` if it was
    ///   gone (no-op) — callers use this to avoid permanently deduping a "shown" that never fired.
    func notifyMessageShown(messageId: String) async -> Bool
}

// MARK: - Implementation

/// Default `VisualInboxProvider` that adapts the internal `VisualInboxRepository` + headless
/// `NotificationInbox` to the SPI value types. Constructed from the shared DI graph.
final class VisualInboxProviderImpl: VisualInboxProvider, @unchecked Sendable {
    private let repository: VisualInboxRepository
    private let inbox: NotificationInbox
    private let inAppMessageManager: InAppMessageManager

    /// De-dupe guard for `observe()` emissions. Guarded by `lastSnapshotLock` because the two merge
    /// child tasks can recompute concurrently.
    private var lastEmittedSnapshot: VisualInboxSnapshot?
    private let lastSnapshotLock = NSLock()

    init(
        repository: VisualInboxRepository,
        inbox: NotificationInbox,
        inAppMessageManager: InAppMessageManager
    ) {
        self.repository = repository
        self.inbox = inbox
        self.inAppMessageManager = inAppMessageManager
    }

    func load() async {
        await repository.enableAndLoad()
    }

    func observe() -> AsyncStream<VisualInboxSnapshot> {
        AsyncStream { continuation in
            // Merge two trigger sources — repository.loadStateChanges() (enablement/visibility flips)
            // and the in-app store's inboxMessages (message-set / opened-state changes) — each
            // re-reading the current cached state to emit a coalesced, de-duped snapshot. No fetch.
            let driver = Task { [repository, weak self] in
                let loadStateChanges = await repository.loadStateChanges()
                // Bridge store subscription callbacks into this task via a local continuation.
                // (`makeStream()` is iOS 17+, so capture the continuation from the builder instead to
                // stay within the SDK's iOS-13-compatible source floor.)
                var storeContinuation: AsyncStream<Void>.Continuation!
                let storeTicks = AsyncStream<Void> { storeContinuation = $0 }
                let subscriber = InAppMessageStoreSubscriber { _ in
                    storeContinuation.yield(())
                }
                let subscriptionTask = self?.inAppMessageManager.subscribe(
                    keyPath: \.inboxMessages,
                    subscriber: subscriber
                )

                // One child task per source forwards into the recompute pump (cancellation-safe).
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for await _ in loadStateChanges {
                            await self?.emitSnapshot(into: continuation)
                        }
                    }
                    group.addTask {
                        for await _ in storeTicks {
                            await self?.emitSnapshot(into: continuation)
                        }
                    }
                    await group.waitForAll()
                }

                withExtendedLifetime(subscriber) {
                    // Explicitly unsubscribe (not just cancel the subscribe Task) so the store stops
                    // notifying this subscriber once the overlay's observe() shuts down.
                    _ = self?.inAppMessageManager.unsubscribe(subscriber: subscriber)
                    subscriptionTask?.cancel()
                }
                storeContinuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                driver.cancel()
            }
        }
    }

    /// Last emitted snapshot, used to de-dupe. Accessed only from the single `observe()` driver
    /// task's child tasks; serialized by the `lastSnapshotLock` since those run concurrently.
    private func emitSnapshot(into continuation: AsyncStream<VisualInboxSnapshot>.Continuation) async {
        let snapshot = await currentSnapshot()
        lastSnapshotLock.lock()
        let changed = lastEmittedSnapshot == nil || lastEmittedSnapshot != snapshot
        if changed { lastEmittedSnapshot = snapshot }
        lastSnapshotLock.unlock()
        guard changed else { return }
        continuation.yield(snapshot)
    }

    /// Reads the current cached overlay state into one coalesced snapshot. Cache-only (no network).
    ///
    /// The message list is read ONCE (a single `repository.jistMessages()` read) and both the
    /// snapshot messages and `unopenedCount` are derived from that same array. Reading the list and
    /// the count via separate reads could observe a store change in between and produce a badge that
    /// disagrees with the list it's shown next to; deriving both from one read keeps them consistent.
    private func currentSnapshot() async -> VisualInboxSnapshot {
        async let state = self.state()
        async let jistMessages = repository.jistMessages()
        async let templates = templatesJSON()
        async let theme = themeJSON()

        let resolvedMessages = await jistMessages
        let snapshotMessages = resolvedMessages.map {
            VisualInboxMessageSnapshot(
                id: $0.queueId,
                type: $0.type,
                properties: $0.properties,
                opened: $0.opened,
                sentAt: $0.sentAt
            )
        }
        let unopened = resolvedMessages.filter { !$0.opened }.count

        return await VisualInboxSnapshot(
            state: state,
            messages: snapshotMessages,
            unopenedCount: unopened,
            templatesJSON: templates,
            themeJSON: theme
        )
    }

    func state() async -> VisualInboxState {
        await repository.loadState.asSPIState
    }

    func messages() async -> [VisualInboxMessageSnapshot] {
        await repository.jistMessages().map {
            VisualInboxMessageSnapshot(
                id: $0.queueId,
                type: $0.type,
                properties: $0.properties,
                opened: $0.opened,
                sentAt: $0.sentAt
            )
        }
    }

    func unopenedCount() async -> Int {
        await repository.jistMessages().filter { !$0.opened }.count
    }

    func templatesJSON() async -> [String: Any]? {
        await repository.templatesRegistry()?.raw
    }

    func themeJSON() async -> [String: Any]? {
        await repository.branding()?.theme
    }

    func brandingChrome() async -> VisualInboxChrome? {
        guard let branding = await repository.branding() else { return nil }
        let chrome = branding.chrome
        return VisualInboxChrome(
            bellBackground: chrome.floatingIcon.background,
            bellIconColor: chrome.floatingIcon.color,
            panelBackground: chrome.background,
            dividerColor: chrome.dividerColor ?? chrome.borderColor,
            badgeBackground: chrome.unreadIndicator?.background,
            cornerRadius: chrome.cornerRadius,
            darkModePattern: branding.darkModePattern
        )
    }

    @discardableResult
    func markOpened(messageId: String) async -> Bool {
        // Resolve the full InboxMessage from current state so we reuse the existing headless
        // markOpened plumbing (which dispatches the .updateOpened action). No new mutation path.
        let state = await inAppMessageManager.state
        guard let message = state.inboxMessages.first(where: { $0.queueId == messageId }) else {
            // Message no longer in the store → nothing to mark. Report no-op so the caller doesn't
            // permanently dedupe a mark that never applied.
            return false
        }
        inbox.markMessageOpened(message: message)
        return true
    }

    @discardableResult
    func dismiss(messageId: String) async -> Bool {
        // Resolve the full InboxMessage from current state so we reuse the existing headless
        // markMessageDeleted plumbing (which dispatches the .deleteMessage action). No new mutation
        // path. The store change then flows through observe() → the message leaves the selection →
        // computeLoadState empties → .hidden when it was the last message.
        let state = await inAppMessageManager.state
        guard let message = state.inboxMessages.first(where: { $0.queueId == messageId }) else {
            // Message no longer in the store → nothing to delete. Report no-op so the caller doesn't
            // permanently dedupe a dismiss that never applied.
            return false
        }
        inbox.markMessageDeleted(message: message)
        return true
    }

    func handleMessageAction(messageId: String, actionName: String, actionValue: String) async -> VisualInboxActionOutcome {
        // Resolve the full InboxMessage from current state so we can (a) track the click via the
        // existing headless plumbing and (b) hand the host listener a real message. No new path.
        let state = await inAppMessageManager.state
        guard let message = state.inboxMessages.first(where: { $0.queueId == messageId }) else {
            // Message gone from the store (e.g. dismissed between render and tap): don't track or
            // navigate — its row is on its way out.
            return .messageMissing
        }
        // Track a "clicked" metric for the non-dismiss action via the existing headless
        // trackMessageClicked plumbing (dispatches the .trackClicked action). Always tracked,
        // independent of whether the host intercepts the action below.
        inbox.trackMessageClicked(message: message, actionName: actionName)
        // Forward to the host listener on the main actor: this runs from an async Task off the main
        // thread, but the tap originated on the UI and hosts expect a main-thread callback. If it
        // handles the action, the overlay suppresses default navigation.
        let handled = await MainActor.run {
            inbox.notifyMessageActionTaken(message: message, actionValue: actionValue, actionName: actionName)
        }
        return handled ? .handledByHost : .notHandled
    }

    func notifyMessageShown(messageId: String) async -> Bool {
        // Resolve the full InboxMessage so the host listener receives a real message. The headless
        // plumbing dedupes "shown" per id, so calling this on every render is safe.
        let state = await inAppMessageManager.state
        guard let message = state.inboxMessages.first(where: { $0.queueId == messageId }) else {
            // Message gone from the store → nothing to notify. Report no-op so the caller doesn't
            // permanently dedupe a "shown" that never fired.
            return false
        }
        inbox.notifyMessageShown(message: message)
        return true
    }
}

private extension VisualInboxLoadState {
    /// Maps the internal load state to the SPI value type.
    var asSPIState: VisualInboxState {
        switch self {
        case .idle: return .idle
        case .loading: return .loading
        case .visible(let count): return .visible(messageCount: count)
        case .hidden(let reason): return .hidden(reason: reason)
        }
    }
}

// MARK: - DI entry point

@_spi(VisualInbox)
public extension DIGraphShared {
    /// The cross-module Visual Inbox provider, resolved from the shared graph. Used by the overlay
    /// UI module; not registered in the generated graph because the SPI value types are not part of
    /// the AutoMockable/Sourcery surface.
    var visualInboxProvider: VisualInboxProvider {
        VisualInboxProviderImpl(
            repository: visualInboxRepository,
            inbox: notificationInbox,
            inAppMessageManager: inAppMessageManager
        )
    }
}
