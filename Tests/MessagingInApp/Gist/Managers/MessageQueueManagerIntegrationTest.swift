@testable import CioInternalCommon
@testable import CioMessagingInApp
import SharedTests
import XCTest

class MessageQueueManagerIntegrationTests: IntegrationTest {
    var manager: MessageQueueManager!

    var sampleFetchResponseBody: String {
        SampleDataFilesUtil(fileStore: diGraphShared.fileStorage).readFileContents(fileName: "fetch_response.json", subdirectory: "InAppUserQueue")
    }

    override func setUp() {
        super.setUp()

        setupManager()

        UserManager().setUserToken(userToken: .random) // Set a user token so manager can perform user queue fetches.
    }

    // MARK: fetch user messages from backend services

    func test_fetch_givenHTTPResponse200_expectSetLocalMessageStoreFromFetchResponse() {
        XCTAssertTrue(manager.localMessageStore.isEmpty)

        setupHttpResponse(code: 200, body: sampleFetchResponseBody.data)
        manager.fetchUserMessages()

        XCTAssertEqual(manager.localMessageStore.count, 2)
    }

    func test_fetch_givenHTTPResponse204_expectEmptyResponse_expectResetLocalMessageStore() {
        XCTAssertTrue(manager.localMessageStore.isEmpty)

        setupHttpResponse(code: 200, body: sampleFetchResponseBody.data)
        manager.fetchUserMessages()

        XCTAssertEqual(manager.localMessageStore.count, 2)

        setupHttpResponse(code: 204, body: "".data)
        manager.fetchUserMessages()

        XCTAssertTrue(manager.localMessageStore.isEmpty)
    }

    func test_fetch_givenMessageCacheSaved_given304AfterSdkInitialized_expectPopulateLocalMessageStoreFromCache() {
        XCTAssertTrue(manager.localMessageStore.isEmpty)

        setupHttpResponse(code: 200, body: sampleFetchResponseBody.data)
        manager.fetchUserMessages()
        XCTAssertEqual(manager.localMessageStore.count, 2)

        let localMessageStoreBefore304: [Message] = manager.localMessageStore.values.compactMap { $0 }

        setupManager()
        XCTAssertTrue(manager.localMessageStore.isEmpty)

        setupHttpResponse(code: 304, body: "".data)
        manager.fetchUserMessages()

        XCTAssertEqual(manager.localMessageStore.count, 2)
        let localMessageStoreAfter304 = manager.localMessageStore.values

        localMessageStoreBefore304.forEach { message in
            XCTAssertTrue(localMessageStoreAfter304.contains(message))
        }
    }

    // The SDK could receive a 304 and the SDK does not have a previous fetch response cached. Example use cases when this could happen:
    // 1. The user logs out of the SDK and logs in again  with same or different profile.
    // 2. Reinstalls the app and first fetch response is a 304
    func test_fetch_givenNoPreviousCacheSaved_given304AfterSdkInitialized_expectPopulateLocalMessageStoreFromCache() {
        XCTAssertTrue(manager.localMessageStore.isEmpty)

        setupHttpResponse(code: 304, body: "".data)
        manager.fetchUserMessages()

        XCTAssertTrue(manager.localMessageStore.isEmpty)
    }
}

extension MessageQueueManagerIntegrationTests {
    func setupManager() {
        manager = MessageQueueManager()
    }
}
