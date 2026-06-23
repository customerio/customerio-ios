@testable import CioInternalCommon
@testable import CioMessagingInApp
@testable import CioMessagingInAppMocks
import Foundation
import SharedTests
import XCTest

class VisualInboxRepositoryTest: XCTestCase {
    private var networkStub: InboxNetworkClientStub!
    private var inAppMessageManagerMock: InAppMessageManagerMock!
    private var keyValueStore: InMemorySharedKeyValueStorage!
    private var sleeperMock: SleeperMock!
    private var dateUtilStub: DateUtilStub!
    private var logger: Logger!

    private let templatesJSON = #"{ "welcome": [ { "version": 1 } ] }"#
    private let brandingJSON = #"{ "theme": { "radius": 8 }, "patterns": { "inbox": { "background": "white" } } }"#

    override func setUp() {
        super.setUp()
        networkStub = InboxNetworkClientStub()
        inAppMessageManagerMock = InAppMessageManagerMock()
        // The repository subscribes to inboxMessages in its initializer (Fix B); the mock's subscribe
        // returns this Task. Required so makeRepository()'s init-time subscribe doesn't unwrap nil.
        inAppMessageManagerMock.subscribeReturnValue = Task {}
        keyValueStore = InMemorySharedKeyValueStorage()
        sleeperMock = SleeperMock()
        sleeperMock.sleepClosure = { _ in }
        dateUtilStub = DateUtilStub()
        logger = DIGraphShared.shared.logger
    }

    private func makeRepository() -> VisualInboxRepositoryImpl {
        VisualInboxRepositoryImpl(
            networkClient: networkStub,
            inAppMessageManager: inAppMessageManagerMock,
            keyValueStore: keyValueStore,
            sleeper: sleeperMock,
            dateUtil: dateUtilStub,
            logger: logger
        )
    }

    /// One visual-inbox message so the visibility gate's "messages" requirement is satisfied.
    private func sampleVisualMessage(queueId: String = "v") -> InboxMessage {
        InboxMessage(queueId: queueId, deliveryId: nil, expiry: nil, sentAt: Date(timeIntervalSince1970: 100), topics: ["cio_inbox"], type: "card", opened: false, priority: nil, properties: [:])
    }

    /// Sets the user and (by default) one selectable visual-inbox message in state.
    private func setUser(_ userId: String?, withMessages messages: [InboxMessage]? = nil) {
        let resolved = messages ?? [sampleVisualMessage()]
        inAppMessageManagerMock.underlyingState = InAppMessageState().copy(userId: userId, inboxMessages: resolved)
    }

    private func stubSuccess() {
        networkStub.handler = { [templatesJSON, brandingJSON] endpoint, _ in
            endpoint == .getTemplates
                ? InboxNetworkClientStub.response(json: templatesJSON)
                : InboxNetworkClientStub.response(json: brandingJSON)
        }
    }

    // MARK: - Enablement gate

    func test_isInboxEnabled_whenNeverSet_expectFalse() async {
        setUser("user-1")
        let repo = makeRepository()

        let enabled = await repo.isInboxEnabled
        XCTAssertFalse(enabled)
    }

    func test_setInboxEnabled_expectFlagObservable() async {
        setUser("user-1")
        let repo = makeRepository()

        await repo.setInboxEnabled(true)
        let enabled = await repo.isInboxEnabled

        XCTAssertTrue(enabled)
    }

    func test_setInboxEnabled_expectReturnsPreviousValueForTransitionDetection() async {
        setUser("user-1")
        let repo = makeRepository()

        // First write: previously unset -> false (this is a false→true transition).
        let prev1 = await repo.setInboxEnabled(true)
        XCTAssertFalse(prev1)

        // Second write at same value -> previous now true (NOT a transition).
        let prev2 = await repo.setInboxEnabled(true)
        XCTAssertTrue(prev2)
    }

    func test_enableAndLoad_whenDisabled_expectHidden() async {
        setUser("user-1")
        let repo = makeRepository()

        await repo.enableAndLoad()

        let state = await repo.loadState
        XCTAssertEqual(state, .hidden(reason: "inbox disabled"))
        let visible = await repo.isInboxVisible
        XCTAssertFalse(visible)
    }

    func test_enableAndLoad_whenDisabledAfterBeingVisible_expectRecomputesToHidden() async {
        // Regression: once the inbox has rendered visible, a later workspace that DISABLES the inbox
        // must recompute loadState to hidden. enableAndLoad() self-gates on the disabled flag, so
        // calling it after setInboxEnabled(false) flips a previously-visible state to hidden.
        setUser("user-1")
        let repo = makeRepository()
        await repo.setInboxEnabled(true)
        stubSuccess()

        await repo.enableAndLoad()
        let visibleState = await repo.loadState
        XCTAssertEqual(visibleState, .visible(messageCount: 1))

        // Workspace disables the inbox; the next pipeline run recomputes to hidden (not stale visible).
        await repo.setInboxEnabled(false)
        await repo.enableAndLoad()

        let hiddenState = await repo.loadState
        XCTAssertEqual(hiddenState, .hidden(reason: "inbox disabled"))
        let visible = await repo.isInboxVisible
        XCTAssertFalse(visible)
    }

    // MARK: - Fix A: disable during an in-flight revalidation stays hidden

    func test_enableAndLoad_whenDisabledWhileRevalidationInFlight_expectStaysHiddenNotFlippedVisible() async {
        // The inbox is enabled and a revalidation starts; while the fetch is parked, a later poll
        // DISABLES the inbox (enabled=false + loadState hidden). When the parked fetch completes it
        // must NOT flip loadState back to visible — it re-reads the enablement flag and stays hidden.
        setUser("user-1")
        let gatedStub = GatedInboxNetworkClientStub(templatesJSON: templatesJSON, brandingJSON: brandingJSON)
        let repo = VisualInboxRepositoryImpl(
            networkClient: gatedStub,
            inAppMessageManager: inAppMessageManagerMock,
            keyValueStore: keyValueStore,
            sleeper: sleeperMock,
            dateUtil: dateUtilStub,
            logger: logger
        )
        await repo.setInboxEnabled(true)

        // Start the load; it enters the fetch and suspends on the gated network.
        async let load: Void = repo.enableAndLoad()
        await gatedStub.waitUntilFirstCallStarted()

        // A later poll disables the inbox WHILE the fetch is still in flight.
        await repo.setInboxEnabled(false)

        // Release the parked fetch so the revalidation completes.
        gatedStub.release()
        await load

        // The completed (now-stale) fetch must not resolve to visible — it stays hidden.
        let state = await repo.loadState
        XCTAssertEqual(state, .hidden(reason: "inbox disabled"))
        let visible = await repo.isInboxVisible
        XCTAssertFalse(visible)
    }

    func test_enableAndLoad_whenStillEnabledAfterRevalidation_expectVisible() async {
        // Control for the fix above: if the inbox is NOT disabled mid-flight, the revalidation still
        // resolves to visible (the re-read guard only blocks when disabled).
        setUser("user-1")
        let repo = makeRepository()
        await repo.setInboxEnabled(true)
        stubSuccess()

        await repo.enableAndLoad()

        let state = await repo.loadState
        XCTAssertEqual(state, .visible(messageCount: 1))
    }

    // MARK: - Fix B: inbox-message changes (SSE path) recompute loadState without a fetch

    func test_messageChange_whenMessagesBecomeEmpty_expectRecomputesToHiddenWithoutFetch() async {
        // Under SSE, messages arrive via processInboxMessages (a store update) without running the
        // queue HTTP pipeline. The repository subscribes to inboxMessages and re-resolves loadState on
        // change — reusing cached templates/branding, never issuing a network fetch.
        setUser("user-1")
        let repo = makeRepository()
        await repo.setInboxEnabled(true)
        stubSuccess()

        // First load resolves visible and marks the session as revalidated.
        await repo.enableAndLoad()
        let loaded = await repo.loadState
        XCTAssertEqual(loaded, .visible(messageCount: 1))
        let callsAfterLoad = networkStub.calls.count

        // Simulate an SSE-driven store change that empties the inbox, then notify the subscriber the
        // repository registered (mirrors processInboxMessages dispatching a new state).
        inAppMessageManagerMock.underlyingState = InAppMessageState().copy(userId: "user-1", inboxMessages: [])
        await notifyMessageSubscriber()

        // loadState recomputed to hidden (no messages) — purely from the store change, no new fetch.
        let recomputed = await repo.loadState
        XCTAssertEqual(recomputed, .hidden(reason: "no selected messages"))
        XCTAssertEqual(networkStub.calls.count, callsAfterLoad)
    }

    func test_messageChange_whenMessagesReappear_expectRecomputesToVisibleWithoutFetch() async {
        // The reverse transition: an SSE update that adds a message flips hidden→visible with no fetch.
        setUser("user-1", withMessages: [])
        let repo = makeRepository()
        await repo.setInboxEnabled(true)
        stubSuccess()

        await repo.enableAndLoad()
        let loaded = await repo.loadState
        XCTAssertEqual(loaded, .hidden(reason: "no selected messages"))
        let callsAfterLoad = networkStub.calls.count

        inAppMessageManagerMock.underlyingState = InAppMessageState().copy(userId: "user-1", inboxMessages: [sampleVisualMessage()])
        await notifyMessageSubscriber()

        let recomputed = await repo.loadState
        XCTAssertEqual(recomputed, .visible(messageCount: 1))
        XCTAssertEqual(networkStub.calls.count, callsAfterLoad)
    }

    func test_messageChange_whenSessionNotYetRevalidated_expectNoRecomputeAndNoFetch() async {
        // Respect the once-per-session gate: a message change BEFORE the first load must not resolve
        // loadState early (the pending enableAndLoad owns the first resolution) and must not fetch.
        setUser("user-1")
        let repo = makeRepository()
        await repo.setInboxEnabled(true)
        // No enableAndLoad yet → didRevalidateThisSession is false.

        inAppMessageManagerMock.underlyingState = InAppMessageState().copy(userId: "user-1", inboxMessages: [sampleVisualMessage()])
        await notifyMessageSubscriber()

        // Still idle (recompute is a no-op until the first revalidation), and no network calls.
        let state = await repo.loadState
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(networkStub.calls.count, 0)
    }

    /// Invokes the `inboxMessages` subscriber the repository registered in its initializer, simulating
    /// a store update (the SSE path). Yields first so the repo's init `Task` has registered.
    private func notifyMessageSubscriber() async {
        // Let the repository's init-time subscribe Task run and capture the subscriber.
        for _ in 0 ..< 200 where inAppMessageManagerMock.subscribeReceivedArguments == nil {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1000000) // 1ms
        }
        guard let subscriber = inAppMessageManagerMock.subscribeReceivedArguments?.subscriber else {
            XCTFail("repository did not subscribe to inboxMessages")
            return
        }
        subscriber.newState(state: inAppMessageManagerMock.underlyingState)
        // Let the subscriber's recompute Task hop back onto the actor and finish.
        try? await Task.sleep(nanoseconds: 30000000) // 30ms
    }

    // MARK: - Visible: enabled + messages + templates + branding all present

    func test_enableAndLoad_whenEnabledWithMessagesTemplatesAndBranding_expectVisible() async {
        setUser("user-1")
        let repo = makeRepository()
        await repo.setInboxEnabled(true)
        stubSuccess()

        await repo.enableAndLoad()

        let loadState = await repo.loadState
        XCTAssertEqual(loadState, .visible(messageCount: 1))
        let visible = await repo.isInboxVisible
        XCTAssertTrue(visible)

        let registry = await repo.templatesRegistry()
        XCTAssertEqual(registry?.templateNames, ["welcome"])

        let branding = await repo.branding()
        XCTAssertEqual(branding?.theme["radius"] as? Int, 8)
        XCTAssertEqual(branding?.chrome.background, "white")
    }

    func test_enableAndLoad_whenFirstLoadOfSession_expectRevalidatesViaNetwork() async {
        // First load of a session revalidates templates + branding against the server.
        setUser("user-1")
        let repo = makeRepository()
        await repo.setInboxEnabled(true)
        stubSuccess()

        await repo.enableAndLoad()

        XCTAssertEqual(networkStub.callCount(for: .getTemplates), 1)
        XCTAssertEqual(networkStub.callCount(for: .getBranding), 1)
        let state = await repo.loadState
        XCTAssertEqual(state, .visible(messageCount: 1))
    }

    func test_enableAndLoad_whenSecondLoadSameSession_expectServesStoredWithoutNetwork() async {
        // Once-per-session revalidation: a second load in the SAME session serves the stored
        // payload without any further network call (server-decided freshness, no local TTL).
        setUser("user-1")
        let repo = makeRepository()
        await repo.setInboxEnabled(true)
        stubSuccess()

        await repo.enableAndLoad()
        let firstCallCount = networkStub.calls.count

        // Second call in the same session -> served from the stored payload, no new network calls.
        await repo.enableAndLoad()

        XCTAssertEqual(networkStub.calls.count, firstCallCount)
        let state = await repo.loadState
        XCTAssertEqual(state, .visible(messageCount: 1))
    }

    func test_enableAndLoad_expectBothEndpointsRequested() async {
        setUser("user-1")
        let repo = makeRepository()
        await repo.setInboxEnabled(true)
        stubSuccess()

        await repo.enableAndLoad()

        XCTAssertEqual(networkStub.callCount(for: .getTemplates), 1)
        XCTAssertEqual(networkStub.callCount(for: .getBranding), 1)
    }

    // MARK: - Hidden when any piece missing & uncached

    func test_enableAndLoad_whenTemplatesFailAllRetriesAndNoCache_expectHidden() async {
        setUser("user-1")
        let repo = makeRepository()
        await repo.setInboxEnabled(true)

        networkStub.handler = { endpoint, _ in
            if endpoint == .getTemplates {
                throw InboxNetworkError.httpStatus(500)
            }
            return InboxNetworkClientStub.response(json: #"{ "theme": {}, "patterns": { "inbox": {} } }"#)
        }

        await repo.enableAndLoad()

        let state = await repo.loadState
        XCTAssertEqual(state, .hidden(reason: "templates unavailable"))
        // 3 attempts (default policy maxAttempts).
        XCTAssertEqual(networkStub.callCount(for: .getTemplates), 3)
    }

    func test_enableAndLoad_whenBrandingFailsAllRetriesAndNoCache_expectHidden() async {
        // Branding is REQUIRED-to-render. Missing & uncached branding -> hidden.
        setUser("user-1")
        let repo = makeRepository()
        await repo.setInboxEnabled(true)

        networkStub.handler = { [templatesJSON] endpoint, _ in
            if endpoint == .getBranding {
                throw InboxNetworkError.httpStatus(500)
            }
            return InboxNetworkClientStub.response(json: templatesJSON)
        }

        await repo.enableAndLoad()

        let state = await repo.loadState
        XCTAssertEqual(state, .hidden(reason: "branding unavailable"))
        XCTAssertEqual(networkStub.callCount(for: .getBranding), 3)
    }

    func test_enableAndLoad_whenNoMessages_expectHidden() async {
        // No selectable messages -> hidden even though templates + branding succeed.
        setUser("user-1", withMessages: [])
        let repo = makeRepository()
        await repo.setInboxEnabled(true)
        stubSuccess()

        await repo.enableAndLoad()

        let state = await repo.loadState
        XCTAssertEqual(state, .hidden(reason: "no selected messages"))
    }

    // MARK: - Serve-stale (templates/branding) keeps the inbox visible

    func test_enableAndLoad_whenRevalidationFails_expectServesStoredAndVisible() async {
        setUser("user-1")
        let repo = makeRepository()
        await repo.setInboxEnabled(true)

        // 1) Successful initial revalidation persists templates + branding.
        stubSuccess()
        await repo.enableAndLoad()
        let firstState = await repo.loadState
        XCTAssertEqual(firstState, .visible(messageCount: 1))

        // 2) A fresh repository instance is a NEW session (the gate resets only on process restart),
        //    so it revalidates exactly once. It shares the same persistent store, so the templates +
        //    branding persisted above are still available to serve stale.
        let nextSessionRepo = makeRepository()
        // 3) Both fetches now fail on every retry -> must serve the last-stored payload (serve-stale).
        networkStub.handler = { _, _ in throw InboxNetworkError.httpStatus(500) }
        await nextSessionRepo.enableAndLoad()

        // Stored templates + branding (+ fresh messages from state) -> still visible.
        let state = await nextSessionRepo.loadState
        XCTAssertEqual(state, .visible(messageCount: 1))
        // The failed revalidation re-attempted both endpoints (new session revalidates once).
        XCTAssertEqual(networkStub.callCount(for: .getTemplates), 1 + InboxRetryPolicy.default.maxAttempts)
        XCTAssertEqual(networkStub.callCount(for: .getBranding), 1 + InboxRetryPolicy.default.maxAttempts)
    }

    // MARK: - Messages read live from the headless store

    func test_selectedMessages_whenStateBecomesEmpty_expectEmpty() async {
        // Messages are now read live from the headless in-app store (no bespoke messages cache).
        // Serve-stale for messages is the headless layer's responsibility: a failed poll never
        // re-dispatches messages, so state retains them. An explicitly EMPTY state IS empty.
        setUser("user-1")
        let repo = makeRepository()

        let first = await repo.selectedMessages()
        XCTAssertEqual(first.map(\.queueId), ["v"])

        inAppMessageManagerMock.underlyingState = InAppMessageState().copy(userId: "user-1", inboxMessages: [])

        let second = await repo.selectedMessages()
        XCTAssertEqual(second.map(\.queueId), [])
    }

    func test_enableAndLoad_whenStateRetainsMessages_expectStillVisible() async {
        // A failed refresh keeps the headless store's last messages, so the inbox stays visible as
        // long as state still reports them (templates + branding served from the stored payload).
        setUser("user-1")
        let repo = makeRepository()
        await repo.setInboxEnabled(true)
        stubSuccess()

        await repo.enableAndLoad()
        let firstState = await repo.loadState
        XCTAssertEqual(firstState, .visible(messageCount: 1))

        // State still reports the message (headless serve-stale through a failed poll).
        await repo.enableAndLoad()

        let state = await repo.loadState
        XCTAssertEqual(state, .visible(messageCount: 1))
    }

    // MARK: - Workspace-scoped cache (not per-user)

    func test_cache_whenUserSwitches_expectWorkspaceScopedCacheRetained() async {
        setUser("user-1")
        let repo = makeRepository()
        await repo.setInboxEnabled(true)
        stubSuccess()
        await repo.enableAndLoad()
        let user1Templates = await repo.templatesRegistry()
        XCTAssertNotNil(user1Templates)

        // Switch user: render assets + enablement are workspace-scoped, so they are retained
        // (no per-user namespacing). This matches the headless inbox's workspace-scoped storage.
        setUser("user-2")
        let user2Templates = await repo.templatesRegistry()
        XCTAssertEqual(user2Templates?.templateNames, user1Templates?.templateNames)

        let user2Enabled = await repo.isInboxEnabled
        XCTAssertTrue(user2Enabled)
    }

    // MARK: - Selection + Jist exposure

    func test_selectedMessages_expectVisualInboxFilteringApplied() async {
        let visual = InboxMessage(queueId: "v", deliveryId: nil, expiry: nil, sentAt: Date(timeIntervalSince1970: 100), topics: ["cio_inbox_news"], type: "card", opened: false, priority: 1, properties: [:])
        let headless = InboxMessage(queueId: "h", deliveryId: nil, expiry: nil, sentAt: Date(timeIntervalSince1970: 200), topics: ["promos"], type: "card", opened: false, priority: 1, properties: [:])
        inAppMessageManagerMock.underlyingState = InAppMessageState().copy(userId: "user-1", inboxMessages: [visual, headless])
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 0)
        let repo = makeRepository()

        let messages = await repo.selectedMessages()

        XCTAssertEqual(messages.map(\.queueId), ["v"])
    }

    // MARK: - In-flight guard prevents duplicate concurrent fetches

    func test_enableAndLoad_whenCalledConcurrently_expectSingleFetchPerEndpoint() async {
        setUser("user-1")
        let gatedStub = GatedInboxNetworkClientStub(templatesJSON: templatesJSON, brandingJSON: brandingJSON)
        let repo = VisualInboxRepositoryImpl(
            networkClient: gatedStub,
            inAppMessageManager: inAppMessageManagerMock,
            keyValueStore: keyValueStore,
            sleeper: sleeperMock,
            dateUtil: dateUtilStub,
            logger: logger
        )
        await repo.setInboxEnabled(true)

        // Launch two concurrent loads. The first enters the fetch and suspends on the gated network;
        // the second must hit the in-flight guard and NOT launch its own fetch.
        async let first: Void = repo.enableAndLoad()
        async let second: Void = repo.enableAndLoad()

        // Give both tasks time to reach the actor and the guard before releasing the network.
        await gatedStub.waitUntilFirstCallStarted()
        gatedStub.release()

        _ = await(first, second)

        // Exactly one fetch per endpoint despite two concurrent enableAndLoad calls.
        XCTAssertEqual(gatedStub.callCount(for: .getTemplates), 1)
        XCTAssertEqual(gatedStub.callCount(for: .getBranding), 1)

        let state = await repo.loadState
        XCTAssertEqual(state, .visible(messageCount: 1))
    }

    func test_jistMessages_expectTypedPropertiesPreserved() async {
        let props: [String: Any] = ["cta": ["label": "Open", "enabled": true]]
        let msg = InboxMessage(queueId: "v", deliveryId: nil, expiry: nil, sentAt: Date(timeIntervalSince1970: 100), topics: ["cio_inbox"], type: "card", opened: false, priority: nil, properties: props)
        inAppMessageManagerMock.underlyingState = InAppMessageState().copy(userId: "user-1", inboxMessages: [msg])
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 0)
        let repo = makeRepository()

        let jist = await repo.jistMessages()

        XCTAssertEqual(jist.count, 1)
        let cta = jist[0].properties["cta"] as? [String: Any]
        XCTAssertEqual(cta?["enabled"] as? Bool, true)
    }

    // MARK: - Reactive observation

    func test_loadStateChanges_whenStateResolves_expectEmission() async {
        setUser("user-1")
        let repo = makeRepository()
        await repo.setInboxEnabled(true)
        stubSuccess()

        let stream = await repo.loadStateChanges()
        var iterator = stream.makeAsyncIterator()
        // First emission fires on subscribe (current state).
        _ = await iterator.next()

        await repo.enableAndLoad()

        // A subsequent emission is produced when loadState is recomputed.
        let tick = await iterator.next()
        XCTAssertNotNil(tick)
        let state = await repo.loadState
        XCTAssertEqual(state, .visible(messageCount: 1))
    }
}
