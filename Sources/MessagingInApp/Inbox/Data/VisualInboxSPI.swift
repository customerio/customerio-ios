import CioInternalCommon
import Foundation

// MARK: - Visual Inbox cross-module SPI

// The ONLY bridge the Visual Inbox overlay UI module (`CioMessagingInbox`) uses to reach the in-app
// data layer. It is gated behind `@_spi(VisualInbox)` so it stays off the public SDK surface (only a
// sibling module that writes `@_spi(VisualInbox) import CioMessagingInApp` can see it). The internal
// data-layer types stay `internal`; this layer exposes plain Foundation value types instead, leaving
// the headless public `NotificationInbox` API untouched.

/// Visibility/loading signal the overlay renders from. Mirrors the internal `VisualInboxLoadState`
/// but is a self-contained SPI value type (no internal types leak across the module boundary).
@_spi(VisualInbox)
public enum VisualInboxState: Equatable {
    /// Nothing fetched yet for the current user.
    case idle
    /// A fetch is in flight — the overlay shows a loading affordance.
    case loading
    /// Fully renderable: enabled, with messages + templates + branding all available.
    case visible(messageCount: Int)
    /// Not renderable (disabled, or any of messages/templates/branding missing). The overlay hides
    /// all chrome. `reason` is diagnostic only. This is NOT an error state.
    case hidden(reason: String)

    /// Whether the overlay should show the inbox chrome (bell + panel).
    public var isVisible: Bool {
        if case .visible = self { return true }
        return false
    }
}

/// A single inbox message, flattened to the minimum the overlay needs to render it via Jist.
///
/// `properties` is preserved as a typed `[String: Any]` (nested objects/arrays/numbers/bools/dates
/// intact — no string flattening) so the overlay can decode it into Jist's `[String: JistValue]`.
@_spi(VisualInbox)
public struct VisualInboxMessageSnapshot: Identifiable {
    /// Stable identifier (the underlying message's queueId).
    public let id: String
    /// Jist message type — selects a template from the registry.
    public let type: String
    /// Typed, nested-preserving properties handed to the Jist renderer.
    public let properties: [String: Any]
    /// Whether the user has opened this message.
    public let opened: Bool
    /// Original send time.
    public let sentAt: Date

    public init(id: String, type: String, properties: [String: Any], opened: Bool, sentAt: Date) {
        self.id = id
        self.type = type
        self.properties = properties
        self.opened = opened
        self.sentAt = sentAt
    }
}

/// A single coalesced snapshot of everything the overlay renders from, emitted by
/// ``VisualInboxProvider/observe()`` whenever the underlying data layer changes.
///
/// Bundling state + messages + count + rendering inputs into one value lets the overlay model
/// publish atomically (one `@Published` write per emission) and lets the provider de-dupe emissions
/// (only forward an emission when the snapshot actually differs from the last one).
@_spi(VisualInbox)
public struct VisualInboxSnapshot: Equatable {
    public let state: VisualInboxState
    public let messages: [VisualInboxMessageSnapshot]
    public let unopenedCount: Int
    /// Raw templates registry JSON, decoded by the overlay into Jist types.
    public let templatesJSON: [String: Any]?
    /// Raw branding theme JSON, decoded by the overlay into Jist types.
    public let themeJSON: [String: Any]?

    public init(
        state: VisualInboxState,
        messages: [VisualInboxMessageSnapshot],
        unopenedCount: Int,
        templatesJSON: [String: Any]?,
        themeJSON: [String: Any]?
    ) {
        self.state = state
        self.messages = messages
        self.unopenedCount = unopenedCount
        self.templatesJSON = templatesJSON
        self.themeJSON = themeJSON
    }

    /// Structural equality used purely to de-dupe emissions. Compares every render-affecting field:
    /// state, count, per-message identity/opened/type AND the render payload (each message's
    /// `properties` plus the raw `templatesJSON`/`themeJSON`). Content-only changes — e.g. a Jist row's
    /// properties or an updated template/theme arriving while `state`/ids are unchanged — must count as
    /// DIFFERENT so `emitSnapshot` forwards them; otherwise `VisualInboxModel.apply` keeps rendering
    /// stale rows/theme. The `[String: Any]` dictionaries aren't `Equatable`, so they're compared via
    /// `NSDictionary(dictionary:).isEqual`, mirroring `InboxBranding`/`InboxTemplatesRegistry`.
    public static func == (lhs: VisualInboxSnapshot, rhs: VisualInboxSnapshot) -> Bool {
        lhs.state == rhs.state &&
            lhs.unopenedCount == rhs.unopenedCount &&
            lhs.messages.count == rhs.messages.count &&
            zip(lhs.messages, rhs.messages).allSatisfy { l, r in
                l.id == r.id && l.opened == r.opened && l.type == r.type &&
                    NSDictionary(dictionary: l.properties).isEqual(to: r.properties)
            } &&
            jsonEqual(lhs.templatesJSON, rhs.templatesJSON) &&
            jsonEqual(lhs.themeJSON, rhs.themeJSON)
    }

    /// Compares two optional `[String: Any]` render-payload dictionaries (nil == nil, nil != non-nil),
    /// using `NSDictionary.isEqual` for the non-nil case (same approach as the data-layer types).
    private static func jsonEqual(_ lhs: [String: Any]?, _ rhs: [String: Any]?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (let l?, let r?): return NSDictionary(dictionary: l).isEqual(to: r)
        default: return false
        }
    }
}

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

    /// Marks a message opened via the existing headless plumbing (no new mutation path). Looked up
    /// by the snapshot id so the overlay never has to hold an internal `InboxMessage`.
    /// - Returns: `true` if a matching message was still present in the store and the mark was
    ///   issued; `false` if the message was gone (the mark was a no-op). Callers use this to avoid
    ///   permanently deduping a mark that never applied.
    @discardableResult
    func markOpened(messageId: String) async -> Bool
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
