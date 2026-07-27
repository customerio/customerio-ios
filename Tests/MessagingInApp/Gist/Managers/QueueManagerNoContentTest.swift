@testable import CioInternalCommon
@testable import CioMessagingInApp
@testable import CioMessagingInAppMocks
import Foundation
import SharedTests
import XCTest

/// A 204 is an authoritative empty queue (web parity: gist-web handles 204 exactly like a 200 with
/// no messages). It previously fell into the JSON-parse path, which threw — leaving stale inbox rows
/// on screen and skipping the visual-inbox pipeline entirely.
class QueueManagerNoContentTest: UnitTest {
    private var gistQueueNetworkMock: GistQueueNetworkMock!
    private var inAppMessageManagerMock: InAppMessageManagerMock!
    private var repositoryFake: VisualInboxRepositoryFake!
    private var queueManager: QueueManager!

    private var keyValueStore: SharedKeyValueStorage!

    override func setUp() {
        super.setUp()

        keyValueStore = diGraphShared.sharedKeyValueStorage
        gistQueueNetworkMock = GistQueueNetworkMock()
        inAppMessageManagerMock = InAppMessageManagerMock()
        inAppMessageManagerMock.dispatchReturnValue = Task {}
        inAppMessageManagerMock.underlyingState = InAppMessageState()
        repositoryFake = VisualInboxRepositoryFake()

        // The 200 path runs the anonymous-message merge; the mock's return value is implicitly
        // unwrapped, so it has to be stubbed or that path traps.
        let anonymousMessageManagerMock = AnonymousMessageManagerMock()
        anonymousMessageManagerMock.getEligibleMessagesReturnValue = []

        queueManager = QueueManager(
            keyValueStore: keyValueStore,
            gistQueueNetwork: gistQueueNetworkMock,
            inAppMessageManager: inAppMessageManagerMock,
            anonymousMessageManager: anonymousMessageManagerMock,
            inboxMessageCache: InboxMessageCacheManager(keyValueStore: keyValueStore, logger: log),
            visualInboxRepository: repositoryFake,
            logger: log
        )
    }

    func test_fetchUserQueue_whenNoContent_expectInboxClearedAndPipelineRun() async {
        stubResponse(statusCode: 204, body: Data())

        let result = await fetchUserQueue()

        // Success with an empty queue, NOT a parse failure.
        switch result {
        case .success(let messages):
            XCTAssertEqual(messages?.count, 0)
        case .failure(let error):
            XCTFail("expected success for a 204, got \(error)")
        }

        // The inbox was cleared rather than left showing the previous poll's rows ...
        let dispatched = inAppMessageManagerMock.dispatchReceivedInvocations.map(\.action)
        XCTAssertTrue(dispatched.contains { action in
            if case .processInboxMessages(let messages) = action { return messages.isEmpty }
            return false
        }, "expected processInboxMessages([]) to be dispatched, got \(dispatched)")

        // ... and the visual-inbox pipeline still ran so loadState is recomputed.
        await waitUntil { await self.repositoryFake.enableAndLoadCallCount > 0 }
    }

    func test_fetchUserQueue_whenNoContent_expectEnablementHeaderStillApplied() async {
        stubResponse(statusCode: 204, body: Data(), headers: ["x-cio-inbox-enabled": "true"])

        _ = await fetchUserQueue()

        await waitUntil { await self.repositoryFake.setEnabledValues == [true] }
    }

    // A 204 also drops the cached 200 body: otherwise a later 304 re-parses it and republishes the
    // very rows the 204 just cleared.
    func test_fetchUserQueue_whenNoContentThenNotModified_expectNoStaleRepublish() async {
        let body = #"{"inAppMessages":[],"inboxMessages":[{"queueId":"q1","sentAt":"2026-01-01T00:00:00.000Z","topics":["cio_inbox"]}]}"#.data(using: .utf8)!

        // A 200 populates the queue cache with one inbox row.
        stubResponse(statusCode: 200, body: body)
        _ = await fetchUserQueue()
        XCTAssertEqual(dispatchedInboxMessageCounts, [1])

        // The 204 clears the inbox and the cached body with it.
        stubResponse(statusCode: 204, body: Data())
        _ = await fetchUserQueue()
        XCTAssertEqual(dispatchedInboxMessageCounts, [1, 0])

        // The later 304 has nothing cached to serve, so the cleared row cannot come back.
        stubResponse(statusCode: 304, body: Data())
        let result = await fetchUserQueue()

        switch result {
        case .success(let messages):
            XCTAssertNil(messages)
        case .failure(let error):
            XCTFail("expected success for a 304 with no cached body, got \(error)")
        }
        XCTAssertEqual(dispatchedInboxMessageCounts, [1, 0])
    }

    // MARK: - Helpers

    /// Message counts of every `processInboxMessages` dispatched so far, in order.
    private var dispatchedInboxMessageCounts: [Int] {
        inAppMessageManagerMock.dispatchReceivedInvocations.compactMap { invocation in
            if case .processInboxMessages(let messages) = invocation.action { return messages.count }
            return nil
        }
    }

    private func stubResponse(statusCode: Int, body: Data, headers: [String: String] = [:]) {
        gistQueueNetworkMock.requestClosure = { _, _, completion in
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com/api/v1/users")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
            )!
            completion(.success((body, response)))
        }
    }

    private func fetchUserQueue() async -> Result<[Message]?, Error> {
        await withCheckedContinuation { continuation in
            queueManager.fetchUserQueue(state: InAppMessageState()) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func waitUntil(_ condition: @escaping () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0 ..< 200 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 5000000) // 5ms
        }
        XCTFail("condition never became true", file: file, line: line)
    }
}

/// Minimal `VisualInboxRepository` stand-in recording the calls the queue pipeline makes.
/// Hand-rolled because the protocol's `async` members are not expressible by the mock template.
private actor VisualInboxRepositoryFake: VisualInboxRepository {
    private(set) var enableAndLoadCallCount = 0
    private(set) var setEnabledValues: [Bool] = []
    private var enabled = false

    var isInboxEnabled: Bool { enabled }
    var loadState: VisualInboxLoadState { .idle }
    var isInboxVisible: Bool { false }

    func enableAndLoad() async {
        enableAndLoadCallCount += 1
    }

    func selectedMessages() async -> [InboxMessage] {
        []
    }

    func jistMessages() async -> [JistInboxMessage] {
        []
    }

    func templatesRegistry() async -> InboxTemplatesRegistry? {
        nil
    }

    func branding() async -> InboxBranding? {
        nil
    }

    @discardableResult
    func setInboxEnabled(_ enabled: Bool) async -> Bool {
        let previous = self.enabled
        self.enabled = enabled
        setEnabledValues.append(enabled)
        return previous
    }

    func loadStateChanges() async -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}
