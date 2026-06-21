import CioInternalCommon
import Foundation

/// Read-facing API the visual-inbox overlay consumes from the data layer.
///
/// The visual inbox is a thin layer over the headless inbox: messages are read live from the
/// headless message source (the in-app store) and selected/sorted on read; only the render assets
/// (templates registry + branding) and the enablement flag are cached here, reusing the same
/// key-value persistence the headless inbox uses for its network responses.
///
/// Exposes:
///  - `isInboxEnabled`: enablement gate the UI can gate/observe on.
///  - `loadState`: drives loading/visible/hidden UI (single decision point; see `VisualInboxLoadState`).
///  - `isInboxVisible`: convenience visibility signal derived from `loadState`.
///  - selected/sorted/typed inbox messages (`selectedMessages` / `jistMessages`).
///  - raw templates registry (`templatesRegistry`) and `branding`.
///
/// Mutations (markOpened/markDeleted/trackClicked) are intentionally **not** re-implemented here;
/// callers reuse the existing `NotificationInbox` plumbing.
protocol VisualInboxRepository: AnyObject, Sendable {
    /// Whether the inbox feature is enabled for the current workspace (from `x-cio-inbox-enabled`, cached).
    var isInboxEnabled: Bool { get async }

    /// Current load state for the visual inbox (idle/loading/visible/hidden).
    var loadState: VisualInboxLoadState { get async }

    /// Whether the inbox should be shown by the overlay UI (derived from `loadState`).
    var isInboxVisible: Bool { get async }

    /// Loads the visual inbox. Revalidates templates + branding (in parallel) against the server
    /// **once per session**, persists the result, and updates `loadState`.
    /// Subsequent same-session loads serve the stored payload without a network call. Idempotent.
    func enableAndLoad() async

    /// Visual-inbox messages: prefix-filtered, expiry-dropped, priority asc → sentAt desc.
    func selectedMessages() async -> [InboxMessage]

    /// Visual-inbox messages adapted to Jist types (typed/nested properties preserved).
    func jistMessages() async -> [JistInboxMessage]

    /// Raw templates registry handed to the inbox module (un-decoded JSON), or nil if unavailable.
    func templatesRegistry() async -> InboxTemplatesRegistry?

    /// Branding (theme + patterns), or nil if unavailable.
    func branding() async -> InboxBranding?

    /// Records the enablement flag read from the queue response headers (persisted, no expiry).
    /// - Returns: the previously-stored enablement value (defaulting to `false` when unset),
    ///   so callers can detect a `false → true` transition.
    @discardableResult
    func setInboxEnabled(_ enabled: Bool) async -> Bool

    /// Emits once every time `loadState` is (re)computed. The overlay subscribes to react to
    /// enablement/visibility changes without polling; emissions are signals only (the subscriber
    /// reads current cached state) and never trigger a network fetch.
    func loadStateChanges() async -> AsyncStream<Void>
}

// sourcery: InjectRegisterShared = "VisualInboxRepository"
// sourcery: InjectSingleton
/// Default actor-isolated implementation of the visual-inbox data layer. Implemented as an `actor`
/// so all cache reads/writes and load-state transitions are serialized without manual locking.
///
/// Freshness model (matches Android): templates/branding are revalidated against the server
/// **once per session** (first `enableAndLoad()` of the process, via `GistQueueNetwork`); later
/// same-session loads serve the stored payload with no network call. No wall-clock TTL — the
/// in-memory gate resets only on process restart (DI singleton); logout clears persisted assets.
///
/// Serve-stale: a failed poll never dispatches new inbox messages, so the store retains its
/// last-known-good set (persisted via the headless 304 cache); templates/branding fall back to the
/// last stored payload on failed revalidation.
actor VisualInboxRepositoryImpl: VisualInboxRepository {
    private let networkClient: InboxNetworkClient
    private let inAppMessageManager: InAppMessageManager
    private let sleeper: Sleeper
    private let dateUtil: DateUtil
    private let logger: Logger

    /// Workspace-scoped persistent store for render assets + enablement flag (no expiry; serve-stale
    /// source and same-session payload source).
    private let assetsCache: InboxRenderAssetsCache

    private var currentLoadState: VisualInboxLoadState = .idle {
        didSet { loadStateObservers.notify() }
    }

    /// Live observers of `loadState` changes (see `loadStateChanges()`); actor isolation serializes
    /// add/remove/notify, so no manual locking.
    private var loadStateObservers = VisualInboxLoadStateObservers()

    /// In-flight guard: true while a templates+branding revalidation runs, so overlapping polls
    /// don't launch duplicate fetches (actor isolation makes check+set atomic).
    private var isFetchInFlight = false

    /// Session-scoped revalidation gate: false until this session's first revalidation, then
    /// same-session loads serve the stored payload with no network call. Resets ONLY on process
    /// restart (DI singleton) — i.e. a new session revalidates exactly once.
    private var didRevalidateThisSession = false

    /// Strong reference to the weakly-held in-app store subscriber for inbox-message changes, so
    /// messages arriving via the SSE path (`processInboxMessages`, which skips the queue HTTP
    /// pipeline) still trigger a `loadState` recompute. See `subscribeToInboxMessageChanges`.
    private var messagesSubscriber: InAppMessageStoreSubscriber?

    /// Current time, sourced from the injectable `DateUtil` so tests can control it.
    private func currentDate() -> Date {
        dateUtil.now
    }

    init(
        networkClient: InboxNetworkClient,
        inAppMessageManager: InAppMessageManager,
        keyValueStore: SharedKeyValueStorage,
        sleeper: Sleeper,
        dateUtil: DateUtil,
        logger: Logger
    ) {
        self.networkClient = networkClient
        self.inAppMessageManager = inAppMessageManager
        self.sleeper = sleeper
        self.dateUtil = dateUtil
        self.logger = logger
        self.assetsCache = InboxRenderAssetsCache(keyValueStore: keyValueStore)
        Task { await subscribeToInboxMessageChanges() }
    }

    // MARK: - Message-change observation

    /// Subscribes to the in-app store's `inboxMessages` so the visual inbox stays in sync under the
    /// SSE path. Under SSE, messages arrive via `processInboxMessages` (a store update) without
    /// running the queue HTTP pipeline, so `runInboxPipeline` never recomputes `loadState`. We mirror
    /// `DefaultNotificationInbox`'s subscription and re-resolve `loadState` on each message change.
    ///
    /// Network-free: the recompute reuses the CURRENTLY-CACHED templates/branding + the enabled flag
    /// and the live message selection. It NEVER calls `performRevalidation`, and it respects the
    /// once-per-session gate (`didRevalidateThisSession`) so it cannot trigger a fetch.
    private func subscribeToInboxMessageChanges() {
        let subscriber = InAppMessageStoreSubscriber { [weak self] _ in
            // Hop back onto the actor; recompute reads cached assets + the current enabled flag only.
            Task { [weak self] in
                await self?.recomputeLoadStateFromCurrentMessages()
            }
        }
        messagesSubscriber = subscriber
        inAppMessageManager.subscribe(keyPath: \.inboxMessages, subscriber: subscriber)
    }

    /// Lightweight, network-free `loadState` recompute triggered by an inbox-message change.
    ///
    /// Gated so it can never trigger a fetch and never overrides a disabled inbox:
    ///  - if the inbox is disabled → `.hidden`;
    ///  - if this session has not yet revalidated → no-op (the pending `enableAndLoad` owns the first
    ///    resolution; recomputing here with possibly-empty cache would be premature);
    ///  - otherwise re-resolve from the currently-cached templates/branding + live messages.
    private func recomputeLoadStateFromCurrentMessages() async {
        guard assetsCache.enabledFlag() ?? false else {
            currentLoadState = .hidden(reason: "inbox disabled")
            return
        }
        guard didRevalidateThisSession else { return }
        logger.logWithModuleTag("[CIO-Inbox] inbox messages changed → recomputing loadState (no fetch)", level: .debug)
        await resolveLoadState(templates: cachedTemplates(), branding: cachedBranding())
    }

    // MARK: - Enablement gate

    var isInboxEnabled: Bool {
        get async { assetsCache.enabledFlag() ?? false }
    }

    @discardableResult
    func setInboxEnabled(_ enabled: Bool) async -> Bool {
        let previous = assetsCache.enabledFlag() ?? false
        assetsCache.setEnabled(enabled)
        return previous
    }

    // MARK: - Load state

    var loadState: VisualInboxLoadState {
        get async { currentLoadState }
    }

    var isInboxVisible: Bool {
        get async { currentLoadState.isInboxVisible }
    }

    // MARK: - Reactive observation

    func loadStateChanges() async -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            // Stream builder runs synchronously on the caller; defer register/unregister onto the actor.
            Task { await self.addLoadStateObserver(id: id, continuation: continuation) }
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeLoadStateObserver(id: id) }
            }
        }
    }

    private func addLoadStateObserver(id: UUID, continuation: AsyncStream<Void>.Continuation) {
        loadStateObservers.add(id: id, continuation: continuation)
    }

    private func removeLoadStateObserver(id: UUID) {
        loadStateObservers.remove(id: id)
    }

    // MARK: - Loading

    func enableAndLoad() async {
        // Gate: if disabled, the inbox is hidden (not an error).
        guard assetsCache.enabledFlag() ?? false else {
            logger.logWithModuleTag("[CIO-Inbox] enableAndLoad skipped: inbox disabled for current workspace → hidden", level: .debug)
            currentLoadState = .hidden(reason: "inbox disabled")
            return
        }

        // Stored last-known payloads (serve-stale source and same-session payload source).
        let storedTemplates = cachedTemplates()
        let storedBranding = cachedBranding()

        // Once-per-session gate: after this session has already revalidated, serve the stored
        // payload without a network call (server-decided freshness; no wall-clock TTL).
        if didRevalidateThisSession {
            logger.logWithModuleTag("[CIO-Inbox] enableAndLoad served from stored payload (already revalidated this session)", level: .debug)
            await resolveLoadState(templates: storedTemplates, branding: storedBranding)
            return
        }

        // In-flight guard: if a revalidation is already running, don't launch a duplicate one. The
        // state will be resolved by the revalidation already in progress.
        guard !isFetchInFlight else {
            logger.logWithModuleTag("[CIO-Inbox] enableAndLoad revalidation skipped: one is already in flight", level: .debug)
            return
        }
        isFetchInFlight = true
        defer { isFetchInFlight = false }
        await performRevalidation(staleTemplates: storedTemplates, staleBranding: storedBranding)
    }

    /// Runs the once-per-session network revalidation (templates + branding in parallel), persists
    /// successes, applies the serve-stale preference, marks the session gate, and resolves the
    /// terminal load state. The gate is set regardless of fetch outcome so a failing server does not
    /// cause a tight per-poll retry loop within the same session (failure → serve stale).
    private func performRevalidation(staleTemplates: InboxTemplatesRegistry?, staleBranding: InboxBranding?) async {
        logger.logWithModuleTag("[CIO-Inbox] revalidation triggered (once-per-session): fetching templates + branding", level: .info)
        currentLoadState = .loading
        let retrier = InboxFetchRetrier(sleeper: sleeper, logger: logger)
        let (fetchedTemplates, fetchedBranding) = await fetchTemplatesAndBranding(state: inAppMessageManager.state, retrier: retrier)

        // Serve-stale preference: prefer a just-fetched value; otherwise retain the last cached one.
        let resolvedTemplates = fetchedTemplates ?? staleTemplates
        let resolvedBranding = fetchedBranding ?? staleBranding
        if fetchedTemplates == nil, resolvedTemplates != nil {
            logger.logWithModuleTag("[CIO-Inbox] serve-stale used: templates (fetch failed, last-known-good retained)", level: .info)
        }
        if fetchedBranding == nil, resolvedBranding != nil {
            logger.logWithModuleTag("[CIO-Inbox] serve-stale used: branding (fetch failed, last-known-good retained)", level: .info)
        }

        // Mark the session gate regardless of outcome: this session has now revalidated once.
        // A failed revalidation served stale; we do not re-hit the network again this session
        // (until a process restart reopens the gate).
        didRevalidateThisSession = true

        // Re-read the enablement flag: the inbox may have been DISABLED by a later poll while this
        // revalidation was in flight (enabled=false + loadState=.hidden). Without this guard, a stale
        // in-flight fetch would resolve back to .visible and flip a freshly-hidden inbox visible. The
        // fetched payloads are still persisted above (only the loadState resolution is gated on
        // still-enabled); we simply do not resolve to visible.
        guard assetsCache.enabledFlag() ?? false else {
            logger.logWithModuleTag("[CIO-Inbox] revalidation completed but inbox was disabled mid-flight → staying hidden", level: .debug)
            currentLoadState = .hidden(reason: "inbox disabled")
            return
        }

        await resolveLoadState(templates: resolvedTemplates, branding: resolvedBranding)
    }

    /// Sets the terminal load state from the resolved render assets + live message selection, and
    /// logs the final visibility decision.
    private func resolveLoadState(templates: InboxTemplatesRegistry?, branding: InboxBranding?) async {
        let messages = await selectedMessages()
        currentLoadState = computeLoadState(messages: messages, templates: templates, branding: branding)
        logger.logVisualInboxVisibility(currentLoadState)
    }

    /// The single terminal-behavior decision point — **hidden vs visible**.
    ///
    /// The inbox is VISIBLE iff ALL three are available:
    ///   - messages: >=1 selected message (live from the headless store), AND
    ///   - templates: a fresh/stale cached or just-fetched registry, AND
    ///   - branding: a fresh/stale cached or just-fetched branding (branding is required to render).
    /// If ANY is missing → `.hidden` with a reason. There is NO error UI outcome here.
    private func computeLoadState(
        messages: [InboxMessage],
        templates: InboxTemplatesRegistry?,
        branding: InboxBranding?
    ) -> VisualInboxLoadState {
        if !messages.isEmpty, templates != nil, branding != nil {
            return .visible(messageCount: messages.count)
        }
        // Build a precise reason from the missing input(s) — parity with Android's Hidden(reason).
        var reasons: [String] = []
        if messages.isEmpty { reasons.append("no selected messages") }
        if templates == nil { reasons.append("templates unavailable") }
        if branding == nil { reasons.append("branding unavailable") }
        return .hidden(reason: reasons.joined(separator: ", "))
    }

    /// Runs the templates + branding fetches concurrently and returns both results. The `async let`
    /// pair is confined to this method so the child tasks are created and torn down in a clean LIFO
    /// scope.
    private func fetchTemplatesAndBranding(
        state: InAppMessageState,
        retrier: InboxFetchRetrier
    ) async -> (templates: InboxTemplatesRegistry?, branding: InboxBranding?) {
        async let templatesResult: InboxTemplatesRegistry? = fetchTemplates(state: state, retrier: retrier)
        async let brandingResult: InboxBranding? = fetchBranding(state: state, retrier: retrier)
        return await(templatesResult, brandingResult)
    }

    private func fetchTemplates(state: InAppMessageState, retrier: InboxFetchRetrier) async -> InboxTemplatesRegistry? {
        do {
            let (registry, data) = try await retrier.run(label: "templates") { [networkClient] in
                let (data, _) = try await networkClient.get(endpoint: .getTemplates, state: state)
                guard let registry = InboxTemplatesRegistry.from(jsonData: data) else {
                    throw InboxNetworkError.noResponse
                }
                return (registry, data)
            }
            assetsCache.setData(data, forKey: .inboxTemplatesCache)
            logger.logWithModuleTag("[CIO-Inbox] templates fetch OK: \(registry.templateNames.count) template name(s)", level: .info)
            return registry
        } catch {
            logger.logWithModuleTag("[CIO-Inbox] templates fetch exhausted retries: \(error)", level: .error)
            return nil
        }
    }

    private func fetchBranding(state: InAppMessageState, retrier: InboxFetchRetrier) async -> InboxBranding? {
        do {
            let (branding, data) = try await retrier.run(label: "branding") { [networkClient] in
                let (data, _) = try await networkClient.get(endpoint: .getBranding, state: state)
                guard let branding = InboxBranding.from(jsonData: data) else {
                    throw InboxNetworkError.noResponse
                }
                return (branding, data)
            }
            assetsCache.setData(data, forKey: .inboxBrandingCache)
            logger.logWithModuleTag("[CIO-Inbox] branding fetch OK: parsed branding payload", level: .info)
            return branding
        } catch {
            logger.logWithModuleTag("[CIO-Inbox] branding fetch exhausted retries: \(error)", level: .error)
            return nil
        }
    }

    // MARK: - Exposure

    func selectedMessages() async -> [InboxMessage] {
        // Read messages live from the headless source and apply visual-inbox selection on read.
        // Serve-stale is provided by the headless layer (a failed poll keeps the last-known-good set).
        let state = await inAppMessageManager.state
        let selected = VisualInboxSelector.select(messages: state.inboxMessages, now: currentDate())
        logger.logWithModuleTag(
            "[CIO-Inbox] selection: \(state.inboxMessages.count) state message(s) → \(selected.count) selected (cio_inbox prefix / priority / expiry)",
            level: .debug
        )
        return selected
    }

    func jistMessages() async -> [JistInboxMessage] {
        let selected = await selectedMessages()
        return InboxMessageJistAdapter.toJist(selected)
    }

    func templatesRegistry() async -> InboxTemplatesRegistry? {
        cachedTemplates()
    }

    func branding() async -> InboxBranding? {
        cachedBranding()
    }

    // MARK: - Helpers

    /// The last-known templates registry from the persistent store (no expiry), or nil if none.
    private func cachedTemplates() -> InboxTemplatesRegistry? {
        guard let data = assetsCache.data(forKey: .inboxTemplatesCache) else { return nil }
        return InboxTemplatesRegistry.from(jsonData: data)
    }

    /// The last-known branding from the persistent store (no expiry), or nil if none.
    private func cachedBranding() -> InboxBranding? {
        guard let data = assetsCache.data(forKey: .inboxBrandingCache) else { return nil }
        return InboxBranding.from(jsonData: data)
    }
}
