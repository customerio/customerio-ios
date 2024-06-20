@testable import CioInternalCommon
@testable import CioMessagingInApp
import XCTest

class QueueManagerTests: UnitTest {
    var queueManager: QueueManager!

    let gistQueueNetworkMock = GistQueueNetworkMock()

    override func setUp() {
        super.setUp()

        diGraphShared.override(value: gistQueueNetworkMock, forType: GistQueueNetwork.self)

        queueManager = QueueManager(siteId: "testSiteId", dataCenter: "testDataCenter")
    }

    // MARK: fetchUserQueue

    func test_fetchUserQueue_givenHTTPResponse204_expectEmptyResponse_expectResetCachedResponse() {
        globalDataStore.inAppUserQueueFetchCachedResponse = Data() // Given the cache is not empty
        XCTAssertNotNil(globalDataStore.inAppUserQueueFetchCachedResponse)

        setupHttpResponse(code: 204, body: Data())

        let expectation = self.expectation(description: "Completion handler called")
        queueManager.fetchUserQueue(userToken: "testUserToken") { result in
            switch result {
            case .success(let actualUserQueue):
                // Expect receive empty array response
                XCTAssertEqual(actualUserQueue?.count, 0)
            case .failure:
                XCTFail("Expected success but got failure")
            }
            expectation.fulfill()
        }

        waitForExpectations()

        // Expect cache to be reset
        XCTAssertNil(globalDataStore.inAppUserQueueFetchCachedResponse)
    }

    func test_fetchUserQueue_givenHTTPResponse304_givenPreviouslyCachedResponse_expectReturnCachedResponse() {
        let givenExistingCache = [
            UserQueueResponse(queueId: .random, priority: 1, messageId: .random, properties: nil)
        ]

        setCachedResponse(givenExistingCache)

        setupHttpResponse(code: 304, body: Data())

        let expectation = self.expectation(description: "Completion handler called")
        queueManager.fetchUserQueue(userToken: "testUserToken") { result in
            switch result {
            case .success(let actualUserQueue):
                XCTAssertEqual(actualUserQueue?.count, 1)
                XCTAssertEqual(actualUserQueue![0].queueId, givenExistingCache[0].queueId)
            case .failure:
                XCTFail("Expected success but got failure")
            }
            expectation.fulfill()
        }

        waitForExpectations()

        // Assert cache not modified and ready for next fetch
        XCTAssertEqual(globalDataStore.inAppUserQueueFetchCachedResponse, responseToData(givenExistingCache))
    }

    func test_fetchUserQueue_givenHTTPResponse304_givenNoPreviousCachedResponse_expectReturnNil() {
        globalDataStore.inAppUserQueueFetchCachedResponse = nil

        setupHttpResponse(code: 304, body: Data())

        let expectation = self.expectation(description: "Completion handler called")
        queueManager.fetchUserQueue(userToken: "testUserToken") { result in
            switch result {
            case .success(let actualUserQueue):
                XCTAssertNil(actualUserQueue)
            case .failure:
                XCTFail("Expected success but got failure")
            }
            expectation.fulfill()
        }

        waitForExpectations()
    }

    func test_fetchUserQueue_givenHTTPResponse200_expectUpdatedCache_expectReturnResponse() {
        let newData = [
            UserQueueResponse(queueId: .random, priority: 1, messageId: .random, properties: nil)
        ]

        XCTAssertNil(globalDataStore.inAppUserQueueFetchCachedResponse)

        setupHttpResponse(code: 200, body: responseToData(newData))

        let expectation = self.expectation(description: "Completion handler called")
        queueManager.fetchUserQueue(userToken: "testUserToken") { result in
            switch result {
            case .success(let actualUserQueue):
                XCTAssertEqual(actualUserQueue?.count, 1)
                XCTAssertEqual(actualUserQueue![0].queueId, newData[0].queueId)
            case .failure:
                XCTFail("Expected success but got failure")
            }
            expectation.fulfill()
        }

        waitForExpectations()

        // Assert cache updated
        XCTAssertEqual(globalDataStore.inAppUserQueueFetchCachedResponse, responseToData(newData))
    }
}

extension QueueManagerTests {
    func responseToData(_ response: [UserQueueResponse]) -> Data {
        try! JSONSerialization.data(withJSONObject: response)
    }

    func setCachedResponse(_ response: [UserQueueResponse]) {
        globalDataStore.inAppUserQueueFetchCachedResponse = responseToData(response)
    }

    func setupHttpResponse(code: Int, body: Data) {
        gistQueueNetworkMock.requestClosure = { _, _, _, _, completionHandler in
            let response = HTTPURLResponse(url: URL(string: "https://test.com")!, statusCode: code, httpVersion: nil, headerFields: nil)!

            completionHandler(.success((body, response)))
        }
    }
}
