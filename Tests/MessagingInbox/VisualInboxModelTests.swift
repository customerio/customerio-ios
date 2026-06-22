@_spi(VisualInbox) import CioMessagingInApp
@testable import CioMessagingInbox
import Foundation
import XCTest

/// Coverage for the Visual Inbox overlay state holder.
///
/// `NotificationInboxOverlay` itself holds only SwiftUI `@State`/`@StateObject`; its rendering and
/// lifecycle (`onAppear`, transitions) are not unit-testable here. The testable behavior lives in
/// ``VisualInboxModel``: the read-only message/unopened-count API (item 9), the load → refresh
/// publish cycle (item 11), and the auto-mark-opened dedupe guard (item 8). These tests drive the
/// model against a hand-written fake provider.
@available(iOS 13.0, *)
@MainActor
final class VisualInboxModelTests: XCTestCase {
    // MARK: - refresh / read-only API (items 9, 11)

    func test_refresh_whenProviderVisible_thenPublishesMessagesAndUnopenedCount() async {
        let provider = FakeVisualInboxProvider()
        provider.stubState = .visible(messageCount: 3)
        provider.stubMessages = [
            makeSnapshot(id: "a", opened: false),
            makeSnapshot(id: "b", opened: true),
            makeSnapshot(id: "c", opened: false)
        ]
        let model = VisualInboxModel(provider: provider)

        await model.refresh()

        XCTAssertEqual(model.messages.count, 3)
        XCTAssertEqual(model.unopenedCount, 2)
        XCTAssertEqual(model.state, .visible(messageCount: 3))
    }

    func test_refresh_whenProviderHidden_thenStateIsHidden() async {
        let provider = FakeVisualInboxProvider()
        provider.stubState = .hidden(reason: "no selected messages")
        let model = VisualInboxModel(provider: provider)

        await model.refresh()

        XCTAssertFalse(model.state.isVisible)
        if case .hidden = model.state {} else {
            XCTFail("expected hidden state")
        }
    }

    // MARK: - auto mark-opened dedupe (item 8)

    func test_markVisibleMessagesOpened_whenCalledTwice_thenEachMessageMarkedOnce() async {
        let provider = FakeVisualInboxProvider()
        provider.stubMessages = [
            makeSnapshot(id: "a", opened: false),
            makeSnapshot(id: "b", opened: false),
            makeSnapshot(id: "c", opened: true) // already opened — never marked
        ]
        let model = VisualInboxModel(provider: provider)
        await model.refresh()

        model.markVisibleMessagesOpened()
        await provider.waitForMarks(expected: 2)
        // Second call must be a no-op for already-reserved ids.
        model.markVisibleMessagesOpened()
        await provider.waitForMarks(expected: 2)

        XCTAssertEqual(provider.markedOpenedIds.sorted(), ["a", "b"])
    }

    /// Fix E: a mark that NO-OPs (message no longer in the store → `markOpened` returns false) must
    /// NOT permanently dedupe the id. A later call with the same message still present must retry it.
    func test_markVisibleMessagesOpened_whenMarkNoOps_thenIdStaysRetryable() async {
        let provider = FakeVisualInboxProvider()
        provider.stubMessages = [makeSnapshot(id: "a", opened: false)]
        // First round: "a" is gone from the store, so the mark no-ops.
        provider.missingMessageIds = ["a"]
        let model = VisualInboxModel(provider: provider)
        await model.refresh()

        model.markVisibleMessagesOpened()
        await provider.waitForAttempts(expected: 1)
        // The mark was attempted but did not apply, so nothing recorded and the id is NOT deduped.
        XCTAssertTrue(provider.markedOpenedIds.isEmpty)

        // Second round: "a" is back in the store; the mark must be RE-ISSUED (not permanently deduped).
        provider.missingMessageIds = []
        model.markVisibleMessagesOpened()
        await provider.waitForMarks(expected: 1)

        XCTAssertEqual(provider.markedOpenedIds, ["a"])
        XCTAssertEqual(provider.markAttempts.count, 2) // attempted twice: failed once, then succeeded.
    }

    func test_markVisibleMessagesOpened_whenAllOpened_thenNothingMarked() async {
        let provider = FakeVisualInboxProvider()
        provider.stubMessages = [makeSnapshot(id: "a", opened: true)]
        let model = VisualInboxModel(provider: provider)
        await model.refresh()

        model.markVisibleMessagesOpened()
        // Nothing should be marked; give any (incorrect) async mark a chance to land before asserting.
        try? await Task.sleep(nanoseconds: 20000000) // 20ms

        XCTAssertTrue(provider.markedOpenedIds.isEmpty)
    }

    // MARK: - reactive observe() subscription (the bug fix)

    /// The bug: at launch the data layer is `.hidden` (enablement header not yet returned). When
    /// enablement flips true ~3s later, the overlay must transition hidden→visible automatically.
    /// Here we start the model (hidden), then push a `.visible` snapshot through `observe()` and
    /// assert the published state flips without any second `load()`/recompose.
    func test_observe_whenEnablementFlipsVisibleAfterStart_thenStatePublishesVisible() async {
        let provider = FakeVisualInboxProvider()
        // Initial: hidden (enablement not yet known at launch).
        provider.initialSnapshot = VisualInboxSnapshot(
            state: .hidden(reason: "inbox disabled"),
            messages: [],
            unopenedCount: 0,
            templatesJSON: nil,
            themeJSON: nil
        )
        let model = VisualInboxModel(provider: provider)
        model.start()

        // First emission (initial) should publish hidden.
        await provider.waitForObserverReady()
        await waitUntil { !model.state.isVisible }
        XCTAssertFalse(model.state.isVisible)

        // Enablement flips true: data layer becomes visible with a message.
        provider.emit(VisualInboxSnapshot(
            state: .visible(messageCount: 1),
            messages: [makeSnapshot(id: "a", opened: false)],
            unopenedCount: 1,
            templatesJSON: ["card": [["body": "hi"]]],
            themeJSON: ["bg": "white"]
        ))

        await waitUntil { model.state.isVisible }
        XCTAssertEqual(model.state, .visible(messageCount: 1))
        XCTAssertEqual(model.messages.count, 1)
        XCTAssertEqual(model.unopenedCount, 1)
        // C2: each message's properties are decoded once into Jist data, keyed by id, when messages
        // refresh — so the row body reads a prepared value rather than re-decoding per render.
        XCTAssertNotNil(model.decodedData["a"])

        model.stop()
    }

    /// When opened-state changes (e.g. mark-opened lands), the unread count must update reactively.
    func test_observe_whenOpenedStateChanges_thenUnopenedCountUpdates() async {
        let provider = FakeVisualInboxProvider()
        provider.initialSnapshot = VisualInboxSnapshot(
            state: .visible(messageCount: 2),
            messages: [makeSnapshot(id: "a", opened: false), makeSnapshot(id: "b", opened: false)],
            unopenedCount: 2,
            templatesJSON: ["card": [["body": "hi"]]],
            themeJSON: ["bg": "white"]
        )
        let model = VisualInboxModel(provider: provider)
        model.start()

        await provider.waitForObserverReady()
        await waitUntil { model.unopenedCount == 2 }
        XCTAssertEqual(model.unopenedCount, 2)

        // One message becomes opened — count drops to 1.
        provider.emit(VisualInboxSnapshot(
            state: .visible(messageCount: 2),
            messages: [makeSnapshot(id: "a", opened: true), makeSnapshot(id: "b", opened: false)],
            unopenedCount: 1,
            templatesJSON: ["card": [["body": "hi"]]],
            themeJSON: ["bg": "white"]
        ))

        await waitUntil { model.unopenedCount == 1 }
        XCTAssertEqual(model.unopenedCount, 1)

        model.stop()
    }

    /// Spins until `condition` is true or a generous budget elapses (~2s), yielding the main actor
    /// each iteration so the model can process queued emissions (and any prior test's in-flight
    /// async work can drain) without flaking under load.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0 ..< 400 {
            if condition() { return }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 5000000) // 5ms
        }
    }

    private func makeSnapshot(id: String, opened: Bool) -> VisualInboxMessageSnapshot {
        VisualInboxMessageSnapshot(id: id, type: "test", properties: [:], opened: opened, sentAt: Date())
    }
}

/// Hand-written fake of the `@_spi(VisualInbox)` `VisualInboxProvider`. Avoids the auto-generated
/// mock pipeline so this test target needs no sourcery config.
@available(iOS 13.0, *)
private final class FakeVisualInboxProvider: VisualInboxProvider, @unchecked Sendable {
    var stubState: VisualInboxState = .idle
    var stubMessages: [VisualInboxMessageSnapshot] = []
    var stubTemplates: [String: Any]?
    var stubTheme: [String: Any]?

    private(set) var markedOpenedIds: [String] = []
    private let lock = NSLock()

    /// Ids that `markOpened` should report as a NO-OP (message no longer in the store → returns
    /// false). Empty by default, so every mark "applies". Used by the failed-mark-retry test.
    var missingMessageIds: Set<String> = []

    /// Snapshot emitted to `observe()` subscribers on subscribe.
    var initialSnapshot: VisualInboxSnapshot?
    private var observeContinuation: AsyncStream<VisualInboxSnapshot>.Continuation?
    private let observeLock = NSLock()

    func load() async {}

    func observe() -> AsyncStream<VisualInboxSnapshot> {
        AsyncStream { continuation in
            observeLock.lock()
            observeContinuation = continuation
            let initial = initialSnapshot
            observeLock.unlock()
            if let initial = initial {
                // Keep the one-shot accessors consistent with what `observe()` emits, mirroring
                // production where `refresh()` and `observe()` read the same data layer. Otherwise the
                // model's start-time `load()`→`refresh()` would race and overwrite the snapshot with
                // stale default stubs.
                applyToStubs(initial)
                continuation.yield(initial)
            }
        }
    }

    /// Pushes a snapshot to the active `observe()` subscriber, simulating a data-layer change.
    func emit(_ snapshot: VisualInboxSnapshot) {
        observeLock.lock()
        let continuation = observeContinuation
        observeLock.unlock()
        applyToStubs(snapshot)
        continuation?.yield(snapshot)
    }

    /// Mirrors a snapshot into the one-shot stub fields so `state()/messages()/...` agree with the
    /// stream, matching the production data layer's single source of truth.
    private func applyToStubs(_ snapshot: VisualInboxSnapshot) {
        stubState = snapshot.state
        stubMessages = snapshot.messages
        stubTemplates = snapshot.templatesJSON
        stubTheme = snapshot.themeJSON
    }

    /// Waits until an `observe()` subscriber has wired up its continuation.
    func waitForObserverReady() async {
        for _ in 0 ..< 200 {
            observeLock.lock()
            let ready = observeContinuation != nil
            observeLock.unlock()
            if ready { return }
            try? await Task.sleep(nanoseconds: 1000000) // 1ms
        }
    }

    func state() async -> VisualInboxState {
        stubState
    }

    func messages() async -> [VisualInboxMessageSnapshot] {
        stubMessages
    }

    func unopenedCount() async -> Int {
        stubMessages.filter { !$0.opened }.count
    }

    func templatesJSON() async -> [String: Any]? {
        stubTemplates
    }

    func themeJSON() async -> [String: Any]? {
        stubTheme
    }

    /// Total number of `markOpened` attempts (including no-ops), for the retry test.
    private(set) var markAttempts: [String] = []

    @discardableResult
    func markOpened(messageId: String) async -> Bool {
        lock.lock()
        markAttempts.append(messageId)
        let didMark = !missingMessageIds.contains(messageId)
        if didMark {
            markedOpenedIds.append(messageId)
        }
        lock.unlock()
        return didMark
    }

    /// Waits until the model's detached mark Task reaches the expected number of marks (or a budget
    /// elapses), so assertions are deterministic without relying on a fixed number of yields.
    func waitForMarks(expected: Int) async {
        for _ in 0 ..< 200 {
            lock.lock()
            let count = markedOpenedIds.count
            lock.unlock()
            if count >= expected { return }
            try? await Task.sleep(nanoseconds: 1000000) // 1ms
        }
    }

    /// Waits until the model's mark Task has ATTEMPTED at least `expected` marks (including no-ops).
    func waitForAttempts(expected: Int) async {
        for _ in 0 ..< 200 {
            lock.lock()
            let count = markAttempts.count
            lock.unlock()
            if count >= expected { return }
            try? await Task.sleep(nanoseconds: 1000000) // 1ms
        }
    }
}
