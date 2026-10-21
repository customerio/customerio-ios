@testable import CioInternalCommon
@testable import CioMessagingInApp
@testable import CioMessagingInAppMocks
import Foundation
import SharedTests
import XCTest

/// A 304 replays the last cached 200 body. That body belongs to the identity it was fetched for, so
/// after a user switch a 304 must not serve the previous user's messages.
class QueueManagerCachedResponseTest: UnitTest {
    private var gistQueueNetworkMock: GistQueueNetworkMock!
    private var inAppMessageManagerMock: InAppMessageManagerMock!
    private var queueManager: QueueManager!

    private var keyValueStore: SharedKeyValueStorage!

    private let body = #"{"inAppMessages":[],"inboxMessages":[{"queueId":"q1","sentAt":"2026-01-01T00:00:00.000Z","topics":["cio_inbox"]}]}"#.data(using: .utf8)!

    override func setUp() {
        super.setUp()

        keyValueStore = diGraphShared.sharedKeyValueStorage
        gistQueueNetworkMock = GistQueueNetworkMock()
        inAppMessageManagerMock = InAppMessageManagerMock()
        inAppMessageManagerMock.dispatchReturnValue = Task {}
        inAppMessageManagerMock.underlyingState = InAppMessageState()
        // QueueManager checks the response still belongs to the current identity before using it.
        let manager: InAppMessageManagerMock = inAppMessageManagerMock
        inAppMessageManagerMock.fetchStateClosure = { [weak manager] completion in
            let state = manager?.underlyingState ?? InAppMessageState()
            completion(state)
            return Task { state }
        }

        let anonymousMessageManagerMock = AnonymousMessageManagerMock()
        anonymousMessageManagerMock.getEligibleMessagesReturnValue = []

        queueManager = QueueManager(
            keyValueStore: keyValueStore,
            gistQueueNetwork: gistQueueNetworkMock,
            inAppMessageManager: inAppMessageManagerMock,
            anonymousMessageManager: anonymousMessageManagerMock,
            inboxMessageCache: InboxMessageCacheManager(keyValueStore: keyValueStore, logger: log),
            visualInboxRepository: VisualInboxRepositoryFake(),
            logger: log
        )
    }

    func test_fetchUserQueue_givenNotModifiedForSameUser_expectCachedBodyReused() async {
        stubResponse(statusCode: 200, body: body)
        _ = await fetchUserQueue(state: InAppMessageState(userId: "user-a"))

        stubResponse(statusCode: 304, body: Data())
        let result = await fetchUserQueue(state: InAppMessageState(userId: "user-a"))

        assertSuccessWithQueue(result)
        XCTAssertEqual(dispatchedInboxMessageCounts, [1, 1])
    }

    func test_fetchUserQueue_givenNotModifiedForAnotherUser_expectCachedBodyNotReused() async {
        stubResponse(statusCode: 200, body: body)
        _ = await fetchUserQueue(state: InAppMessageState(userId: "user-a"))

        stubResponse(statusCode: 304, body: Data())
        let result = await fetchUserQueue(state: InAppMessageState(userId: "user-b"))

        assertSuccessWithoutQueue(result)
        XCTAssertEqual(dispatchedInboxMessageCounts, [1])
    }

    func test_fetchUserQueue_givenNotModifiedAfterAnonymousUserIdentified_expectCachedBodyNotReused() async {
        stubResponse(statusCode: 200, body: body)
        _ = await fetchUserQueue(state: InAppMessageState(anonymousId: "anon-1"))

        stubResponse(statusCode: 304, body: Data())
        let result = await fetchUserQueue(state: InAppMessageState(userId: "user-a", anonymousId: "anon-1"))

        assertSuccessWithoutQueue(result)
        XCTAssertEqual(dispatchedInboxMessageCounts, [1])
    }

    func test_fetchUserQueue_givenCachedBodyWithoutOwner_expectReusedOnceThenOwnedByRequester() async {
        // A body cached by an older SDK version, before owners were recorded: replayed for the
        // requester as it always was, and from then on owned by them.
        keyValueStore.setData(body, forKey: .inAppUserQueueFetchCachedResponse)

        stubResponse(statusCode: 304, body: Data())
        let result = await fetchUserQueue(state: InAppMessageState(userId: "user-a"))

        assertSuccessWithQueue(result)
        XCTAssertEqual(dispatchedInboxMessageCounts, [1])
        XCTAssertEqual(keyValueStore.string(.inAppUserQueueFetchCachedResponseOwner), "identified:user-a")

        let otherUserResult = await fetchUserQueue(state: InAppMessageState(userId: "user-b"))
        assertSuccessWithoutQueue(otherUserResult)
        XCTAssertEqual(dispatchedInboxMessageCounts, [1])
    }

    // A response for an identity that is no longer current is discarded before it can touch the
    // cache or the inbox.
    func test_fetchUserQueue_givenUserChangedWhileInFlight_expectNothingCachedOrPublished() async {
        stubResponse(statusCode: 200, body: body, switchingTo: InAppMessageState(userId: "user-b"))

        let result = await fetchUserQueue(state: InAppMessageState(userId: "user-a"))

        assertDiscarded(result)
        XCTAssertEqual(dispatchedInboxMessageCounts, [])
        XCTAssertNil(keyValueStore.data(.inAppUserQueueFetchCachedResponse))
    }

    func test_fetchUserQueue_givenNoContentForPreviousUser_expectCurrentUsersCacheKept() async {
        stubResponse(statusCode: 200, body: body)
        _ = await fetchUserQueue(state: InAppMessageState(userId: "user-b"))

        // user-a's request was in flight when user-b identified; its 204 arrives late.
        stubResponse(statusCode: 204, body: Data(), switchingTo: InAppMessageState(userId: "user-b"))
        let staleResult = await fetchUserQueue(state: InAppMessageState(userId: "user-a"))
        assertDiscarded(staleResult)

        stubResponse(statusCode: 304, body: Data())
        let result = await fetchUserQueue(state: InAppMessageState(userId: "user-b"))

        assertSuccessWithQueue(result)
        XCTAssertEqual(dispatchedInboxMessageCounts, [1, 1])
    }

    func test_clearCachedUserQueue_expectOwnerCleared() async {
        stubResponse(statusCode: 200, body: body)
        _ = await fetchUserQueue(state: InAppMessageState(userId: "user-a"))

        queueManager.clearCachedUserQueue()

        XCTAssertNil(keyValueStore.string(.inAppUserQueueFetchCachedResponseOwner))
    }

    // MARK: - Helpers

    /// A 304 that could not reuse a cached body reports success with no queue.
    private func assertSuccessWithoutQueue(_ result: Result<[Message]?, Error>, file: StaticString = #filePath, line: UInt = #line) {
        switch result {
        case .success(let messages):
            XCTAssertNil(messages, file: file, line: line)
        case .failure(let error):
            XCTFail("expected success, got \(error)", file: file, line: line)
        }
    }

    private func assertDiscarded(_ result: Result<[Message]?, Error>, file: StaticString = #filePath, line: UInt = #line) {
        switch result {
        case .success:
            XCTFail("expected the response to be discarded", file: file, line: line)
        case .failure(let error):
            XCTAssertTrue(error is QueueFetchError, "expected a discard, got \(error)", file: file, line: line)
        }
    }

    private func assertSuccessWithQueue(_ result: Result<[Message]?, Error>, file: StaticString = #filePath, line: UInt = #line) {
        switch result {
        case .success(let messages):
            XCTAssertNotNil(messages, file: file, line: line)
        case .failure(let error):
            XCTFail("expected success, got \(error)", file: file, line: line)
        }
    }

    /// Message counts of every `processInboxMessages` dispatched so far, in order.
    private var dispatchedInboxMessageCounts: [Int] {
        inAppMessageManagerMock.dispatchReceivedInvocations.compactMap { invocation in
            if case .processInboxMessages(let messages) = invocation.action { return messages.count }
            return nil
        }
    }

    /// - Parameter switchingTo: An identity that becomes current while the request is in flight.
    private func stubResponse(statusCode: Int, body: Data, switchingTo: InAppMessageState? = nil) {
        let manager: InAppMessageManagerMock = inAppMessageManagerMock
        gistQueueNetworkMock.requestClosure = { _, _, completion in
            if let switchingTo {
                manager.underlyingState = switchingTo
            }
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com/api/v1/users")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: [:]
            )!
            completion(.success((body, response)))
        }
    }

    /// Requests the queue for `state`, which is the current identity when the request starts.
    private func fetchUserQueue(state: InAppMessageState) async -> Result<[Message]?, Error> {
        inAppMessageManagerMock.underlyingState = state
        return await withCheckedContinuation { continuation in
            queueManager.fetchUserQueue(state: state) { result in
                continuation.resume(returning: result)
            }
        }
    }
}
