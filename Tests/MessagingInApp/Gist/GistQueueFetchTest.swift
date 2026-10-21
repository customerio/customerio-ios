@testable import CioInternalCommon
@testable import CioMessagingInApp
@testable import CioMessagingInAppMocks
import Foundation
import SharedTests
import XCTest

/// Queue fetches for the same identity share one request, a caller that needs newer data gets one
/// follow-up, and a response for an identity that is no longer current is discarded. Requests are
/// held open by a spy, so overlap is decided by the test rather than by timing.
class GistQueueFetchTest: UnitTest {
    private var inAppMessageManagerMock: InAppMessageManagerMock!
    private var sseLifecycleManagerMock: SseLifecycleManagerMock!
    private var queueManagerSpy: QueueManagerSpy!
    private var gist: Gist!
    private var lifecycleStarted: XCTestExpectation!

    private let userA = InAppMessageState(userId: "user-a")

    override func setUp() {
        super.setUp()

        inAppMessageManagerMock = InAppMessageManagerMock()
        inAppMessageManagerMock.subscribeReturnValue = Task {}
        // Gist unsubscribes in deinit.
        inAppMessageManagerMock.unsubscribeReturnValue = Task {}
        inAppMessageManagerMock.dispatchReturnValue = Task {}
        inAppMessageManagerMock.underlyingState = userA
        let manager: InAppMessageManagerMock = inAppMessageManagerMock
        inAppMessageManagerMock.fetchStateClosure = { [weak manager] completion in
            let state = manager?.underlyingState ?? InAppMessageState()
            completion(state)
            return Task { state }
        }

        sseLifecycleManagerMock = SseLifecycleManagerMock()
        let started = expectation(description: "lifecycle manager started")
        lifecycleStarted = started
        sseLifecycleManagerMock.startClosure = { _ in started.fulfill() }

        queueManagerSpy = QueueManagerSpy(
            keyValueStore: diGraphShared.sharedKeyValueStorage,
            gistQueueNetwork: GistQueueNetworkMock(),
            inAppMessageManager: inAppMessageManagerMock,
            anonymousMessageManager: AnonymousMessageManagerMock(),
            inboxMessageCache: InboxMessageCacheManager(keyValueStore: diGraphShared.sharedKeyValueStorage, logger: log),
            visualInboxRepository: VisualInboxRepositoryFake(),
            logger: log
        )

        gist = Gist(
            logger: log,
            gistDelegate: GistDelegateStub(),
            inAppMessageManager: inAppMessageManagerMock,
            queueManager: queueManagerSpy,
            threadUtil: ThreadUtilStub(),
            sseLifecycleManager: sseLifecycleManagerMock,
            applicationStateProvider: ApplicationStateProviderMock()
        )
    }

    override func tearDown() {
        gist = nil
        super.tearDown()
    }

    func test_queueFetch_givenRequestInFlightForSameUser_expectShared() async {
        let queueFetchHandler = await startedQueueFetchHandler()
        queueFetchHandler(userA, false)
        queueFetchHandler(userA, false)
        queueFetchHandler(userA, false)

        XCTAssertEqual(queueManagerSpy.pendingCompletions.count, 1)

        queueManagerSpy.complete(0, with: .success([]))
        XCTAssertEqual(queueManagerSpy.pendingCompletions.count, 1)
    }

    func test_queueFetch_givenPreviousRequestCompleted_expectNewRequest() async {
        let queueFetchHandler = await startedQueueFetchHandler()
        queueFetchHandler(userA, false)
        queueManagerSpy.complete(0, with: .success([]))

        queueFetchHandler(userA, false)

        XCTAssertEqual(queueManagerSpy.pendingCompletions.count, 2)
    }

    func test_queueFetch_givenFailedRequest_expectNextFetchNotBlocked() async {
        let queueFetchHandler = await startedQueueFetchHandler()
        queueFetchHandler(userA, false)
        queueManagerSpy.complete(0, with: .failure(GistNetworkError.serverError))

        queueFetchHandler(userA, false)

        XCTAssertEqual(queueManagerSpy.pendingCompletions.count, 2)
    }

    func test_queueFetch_givenResponseDiscardedForPreviousUser_expectQueueNotCleared() async {
        let queueFetchHandler = await startedQueueFetchHandler()
        queueFetchHandler(userA, false)

        queueManagerSpy.complete(0, with: .failure(QueueFetchError.identityChanged))

        let clears = inAppMessageManagerMock.dispatchReceivedInvocations.filter { invocation in
            if case .clearMessageQueue = invocation.action { return true }
            return false
        }
        XCTAssertTrue(clears.isEmpty)
    }

    func test_queueFetch_givenFreshCallerJoinedInFlightRequest_expectOneFollowUp() async {
        let queueFetchHandler = await startedQueueFetchHandler()
        queueFetchHandler(userA, false)
        queueFetchHandler(userA, true)
        queueFetchHandler(userA, true)
        XCTAssertEqual(queueManagerSpy.pendingCompletions.count, 1)

        queueManagerSpy.complete(0, with: .success([]))
        XCTAssertEqual(queueManagerSpy.pendingCompletions.count, 2)

        queueManagerSpy.complete(1, with: .success([]))
        XCTAssertEqual(queueManagerSpy.pendingCompletions.count, 2)
    }

    func test_queueFetch_givenSameUserThroughout_expectResponseApplied() async {
        let queueFetchHandler = await startedQueueFetchHandler()
        queueFetchHandler(userA, false)

        queueManagerSpy.complete(0, with: .success([Message.random]))

        XCTAssertEqual(processMessageQueueDispatchCount, 1)
    }

    func test_queueFetch_givenUserChangedWhileInFlight_expectResponseDiscarded() async {
        let queueFetchHandler = await startedQueueFetchHandler()
        queueFetchHandler(userA, false)

        inAppMessageManagerMock.underlyingState = InAppMessageState(userId: "user-b")
        queueManagerSpy.complete(0, with: .success([Message.random]))

        XCTAssertEqual(processMessageQueueDispatchCount, 0)
    }

    func test_queueFetch_givenUserChangedWhileInFlight_expectNewUserNotShared() async {
        let queueFetchHandler = await startedQueueFetchHandler()
        queueFetchHandler(userA, false)

        let userB = InAppMessageState(userId: "user-b")
        inAppMessageManagerMock.underlyingState = userB
        queueFetchHandler(userB, false)

        XCTAssertEqual(queueManagerSpy.pendingCompletions.count, 2)
    }

    // MARK: - Helpers

    /// The handler Gist registers with the lifecycle manager, once its start task has run.
    private func startedQueueFetchHandler() async -> (InAppMessageState, Bool) -> Void {
        await fulfillment(of: [lifecycleStarted], timeout: 1)
        return sseLifecycleManagerMock.startReceivedArguments!
    }

    private var processMessageQueueDispatchCount: Int {
        inAppMessageManagerMock.dispatchReceivedInvocations.filter { invocation in
            if case .processMessageQueue = invocation.action { return true }
            return false
        }.count
    }
}

/// Records queue requests without sending them; the test completes each one explicitly.
private class QueueManagerSpy: QueueManager {
    private let completions = CioInternalCommon.Synchronized<[(Result<[Message]?, Error>) -> Void]>([])

    var pendingCompletions: [(Result<[Message]?, Error>) -> Void] {
        completions.wrappedValue
    }

    override func fetchUserQueue(state: InAppMessageState, completionHandler: @escaping (Result<[Message]?, Error>) -> Void) {
        completions.mutating { $0.append(completionHandler) }
    }

    func complete(_ index: Int, with result: Result<[Message]?, Error>) {
        pendingCompletions[index](result)
    }
}

private class GistDelegateStub: GistDelegate {
    func embedMessage(message: Message, elementId: String) {}
    func messageShown(message: Message) {}
    func messageDismissed(message: Message) {}
    func messageError(message: Message) {}
    func action(message: Message, currentRoute: String, action: String, name: String) {}
    func setEventListener(_ eventListener: InAppEventListener?) {}
}
