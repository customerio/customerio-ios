@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

class GistTests: IntegrationTest {
    var gist: Gist!
    var inAppMessageManager: InAppMessageManager!
    var queueManager: QueueManager!
    private let engineWebMock = EngineWebInstanceMock()
    private var engineWebProvider: EngineWebProvider {
        EngineWebProviderStub(engineWebMock: engineWebMock)
    }

    override func setUp() {
        super.setUp()

        // Set up required mocks
        engineWebMock.underlyingView = UIView()
        diGraphShared.override(value: engineWebProvider, forType: EngineWebProvider.self)

        // Set up InAppMessageManager (real implementation for better integration testing)
        inAppMessageManager = InAppMessageStoreManager(
            logger: diGraphShared.logger,
            threadUtil: diGraphShared.threadUtil,
            logManager: diGraphShared.logManager,
            gistDelegate: diGraphShared.gistDelegate
        )

        // Set up QueueManager with mocked network
        queueManager = QueueManager(
            keyValueStore: diGraphShared.sharedKeyValueStorage,
            gistQueueNetwork: gistQueueNetworkMock,
            inAppMessageManager: inAppMessageManager,
            logger: diGraphShared.logger
        )

        // Set up Gist with all dependencies
        gist = Gist(
            logger: diGraphShared.logger,
            gistDelegate: diGraphShared.gistDelegate,
            inAppMessageManager: inAppMessageManager,
            queueManager: queueManager,
            threadUtil: diGraphShared.threadUtil
        )

        setupMocks()
    }

    override func tearDown() {
        gist = nil
        inAppMessageManager = nil
        queueManager = nil

        super.tearDown()
    }

    private func setupMocks() {
        // Mock GistQueueNetwork to simulate successful network response
        gistQueueNetworkMock.requestClosure = { _, _, completion in
            let response = HTTPURLResponse(url: URL(string: "https://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("[]".utf8)
            completion(.success((data, response)))
        }
    }

    // MARK: - Network Request Blocking Tests

    func test_fetchUserMessages_whenMessageFetchingNotPaused_expectNetworkRequestMade() async {
        // Given: User is identified and message fetching is not paused (default state)
        await inAppMessageManager.dispatch(action: .setUserIdentifier(user: "test-user")).value
        await inAppMessageManager.dispatch(action: .resumeMessageFetching).value

        // Reset the mock to clear any previous calls
        gistQueueNetworkMock.resetMock()

        // When: fetchUserMessages is called
        gist.fetchUserMessages()

        // Then: Network request should be made
        await waitForAsync()
        XCTAssertTrue(gistQueueNetworkMock.requestCalled, "Network request should be made when message fetching is not paused")
    }

    func test_fetchUserMessages_whenMessageFetchingPaused_expectNetworkRequestBlocked() async {
        // Given: User is identified and message fetching is paused
        await inAppMessageManager.dispatch(action: .setUserIdentifier(user: "test-user")).value
        await inAppMessageManager.dispatch(action: .pauseMessageFetching).value

        // Reset the mock to clear any previous calls
        gistQueueNetworkMock.resetMock()

        // When: fetchUserMessages is called
        gist.fetchUserMessages()

        // Then: Network request should be blocked
        await waitForAsync()
        XCTAssertFalse(gistQueueNetworkMock.requestCalled, "Network request should be blocked when message fetching is paused")
    }

    func test_fetchUserMessages_whenMessageFetchingResumed_expectNetworkRequestMade() async {
        // Given: User is identified and message fetching starts paused
        await inAppMessageManager.dispatch(action: .setUserIdentifier(user: "test-user")).value
        await inAppMessageManager.dispatch(action: .pauseMessageFetching).value

        // Reset the mock to clear any previous calls
        gistQueueNetworkMock.resetMock()

        // When: fetchUserMessages is called while paused
        gist.fetchUserMessages()
        await waitForAsync()

        // Then: Network request should be blocked initially
        XCTAssertFalse(gistQueueNetworkMock.requestCalled, "Network request should be blocked when paused")

        // And when: Message fetching is resumed
        await inAppMessageManager.dispatch(action: .resumeMessageFetching).value
        gistQueueNetworkMock.resetMock()

        // And: fetchUserMessages is called again
        gist.fetchUserMessages()
        await waitForAsync()

        // Then: Network request should now be made
        XCTAssertTrue(gistQueueNetworkMock.requestCalled, "Network request should be made after resuming")
    }

    func test_fetchUserMessages_whenNoUserId_expectNetworkRequestBlocked() async {
        // Given: No user ID is set (default state)
        // Reset the mock to clear any previous calls
        gistQueueNetworkMock.resetMock()

        // When: fetchUserMessages is called
        gist.fetchUserMessages()

        // Then: Network request should be blocked
        await waitForAsync()
        XCTAssertFalse(gistQueueNetworkMock.requestCalled, "Network request should be blocked when no user ID is set")
    }

    // MARK: - Helper Methods

    private func waitForAsync(timeout: TimeInterval = 1.0) async {
        try? await Task.sleep(nanoseconds: UInt64(timeout * 0.1 * 1000000000))
    }
}
