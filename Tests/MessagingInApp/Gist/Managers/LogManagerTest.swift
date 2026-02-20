@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

class LogManagerTest: UnitTest {
    private var logManager: LogManager!
    private var gistQueueNetworkMock: GistQueueNetworkMock!
    private var inboxMessageCache: InboxMessageCacheManager!
    private var keyValueStorage: SharedKeyValueStorage!
    private var state: InAppMessageState!

    override func setUp() {
        super.setUp()

        keyValueStorage = diGraphShared.sharedKeyValueStorage
        gistQueueNetworkMock = GistQueueNetworkMock()
        inboxMessageCache = InboxMessageCacheManager(
            keyValueStore: keyValueStorage,
            logger: log
        )
        logManager = LogManager(
            gistQueueNetwork: gistQueueNetworkMock,
            inboxMessageCache: inboxMessageCache
        )
        state = InAppMessageState(siteId: "test-site", dataCenter: "US")
    }

    // MARK: - updateInboxMessageOpened Success Tests

    func test_updateInboxMessageOpened_givenSuccessResponse_expectCacheSaved() {
        let queueId = "queue-1"
        let opened = true
        let expectation = XCTestExpectation(description: "Update completes")

        // Mock successful response
        gistQueueNetworkMock.requestClosure = { _, _, completionHandler in
            let response = HTTPURLResponse(
                url: URL(string: "https://test.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            completionHandler(.success((Data(), response)))
        }

        // When
        logManager.updateInboxMessageOpened(state: state, queueId: queueId, opened: opened) { result in
            switch result {
            case .success:
                // Then: Cache should be updated
                XCTAssertEqual(self.inboxMessageCache.getOpenedStatus(queueId: queueId), opened)
                expectation.fulfill()
            case .failure:
                XCTFail("Expected success")
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - updateInboxMessageOpened Failure Tests

    func test_updateInboxMessageOpened_givenNon200Response_expectCacheNotSaved() {
        let queueId = "queue-1"
        let opened = true
        let expectation = XCTestExpectation(description: "Update fails")

        // Verify cache is empty initially
        XCTAssertNil(inboxMessageCache.getOpenedStatus(queueId: queueId))

        // Mock failed response (non-200 status)
        gistQueueNetworkMock.requestClosure = { _, _, completionHandler in
            let response = HTTPURLResponse(
                url: URL(string: "https://test.com")!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            completionHandler(.success((Data(), response)))
        }

        // When
        logManager.updateInboxMessageOpened(state: state, queueId: queueId, opened: opened) { result in
            switch result {
            case .success:
                XCTFail("Expected failure")
            case .failure:
                // Then: Cache should NOT be updated
                XCTAssertNil(self.inboxMessageCache.getOpenedStatus(queueId: queueId))
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func test_updateInboxMessageOpened_givenNetworkError_expectCacheNotSaved() {
        let queueId = "queue-1"
        let opened = true
        let expectation = XCTestExpectation(description: "Update fails with error")

        // Verify cache is empty initially
        XCTAssertNil(inboxMessageCache.getOpenedStatus(queueId: queueId))

        // Mock network error
        gistQueueNetworkMock.requestClosure = { _, _, completionHandler in
            completionHandler(.failure(GistNetworkError.requestFailed))
        }

        // When
        logManager.updateInboxMessageOpened(state: state, queueId: queueId, opened: opened) { result in
            switch result {
            case .success:
                XCTFail("Expected failure")
            case .failure:
                // Then: Cache should NOT be updated
                XCTAssertNil(self.inboxMessageCache.getOpenedStatus(queueId: queueId))
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func test_updateInboxMessageOpened_givenFailureAfterPreviousSuccess_expectCacheNotChanged() {
        let queueId = "queue-1"
        let initialOpened = true
        let newOpened = false
        let expectation1 = XCTestExpectation(description: "First update succeeds")
        let expectation2 = XCTestExpectation(description: "Second update fails")

        // First update succeeds
        gistQueueNetworkMock.requestClosure = { _, _, completionHandler in
            let response = HTTPURLResponse(
                url: URL(string: "https://test.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            completionHandler(.success((Data(), response)))
        }

        logManager.updateInboxMessageOpened(state: state, queueId: queueId, opened: initialOpened) { _ in
            XCTAssertEqual(self.inboxMessageCache.getOpenedStatus(queueId: queueId), initialOpened)
            expectation1.fulfill()
        }

        wait(for: [expectation1], timeout: 1.0)

        // Second update fails
        gistQueueNetworkMock.requestClosure = { _, _, completionHandler in
            let response = HTTPURLResponse(
                url: URL(string: "https://test.com")!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            completionHandler(.success((Data(), response)))
        }

        logManager.updateInboxMessageOpened(state: state, queueId: queueId, opened: newOpened) { _ in
            // Cache should still have the old value
            XCTAssertEqual(self.inboxMessageCache.getOpenedStatus(queueId: queueId), initialOpened)
            expectation2.fulfill()
        }

        wait(for: [expectation2], timeout: 1.0)
    }

    // MARK: - markInboxMessageDeleted Success Tests

    func test_markInboxMessageDeleted_givenSuccessResponse_expectCacheCleared() {
        let queueId = "queue-1"
        let expectation = XCTestExpectation(description: "Delete completes")

        // Setup: Cache has an entry
        inboxMessageCache.saveOpenedStatus(queueId: queueId, opened: true)
        XCTAssertNotNil(inboxMessageCache.getOpenedStatus(queueId: queueId))

        // Mock successful response
        gistQueueNetworkMock.requestClosure = { _, _, completionHandler in
            let response = HTTPURLResponse(
                url: URL(string: "https://test.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            completionHandler(.success((Data(), response)))
        }

        // When
        logManager.markInboxMessageDeleted(state: state, queueId: queueId) { result in
            switch result {
            case .success:
                // Then: Cache should be cleared
                XCTAssertNil(self.inboxMessageCache.getOpenedStatus(queueId: queueId))
                expectation.fulfill()
            case .failure:
                XCTFail("Expected success")
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - markInboxMessageDeleted Failure Tests

    func test_markInboxMessageDeleted_givenNon200Response_expectCacheNotCleared() {
        let queueId = "queue-1"
        let expectation = XCTestExpectation(description: "Delete fails")

        // Setup: Cache has an entry
        inboxMessageCache.saveOpenedStatus(queueId: queueId, opened: true)
        XCTAssertNotNil(inboxMessageCache.getOpenedStatus(queueId: queueId))

        // Mock failed response (non-200 status)
        gistQueueNetworkMock.requestClosure = { _, _, completionHandler in
            let response = HTTPURLResponse(
                url: URL(string: "https://test.com")!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            completionHandler(.success((Data(), response)))
        }

        // When
        logManager.markInboxMessageDeleted(state: state, queueId: queueId) { result in
            switch result {
            case .success:
                XCTFail("Expected failure")
            case .failure:
                // Then: Cache should NOT be cleared
                XCTAssertNotNil(self.inboxMessageCache.getOpenedStatus(queueId: queueId))
                XCTAssertEqual(self.inboxMessageCache.getOpenedStatus(queueId: queueId), true)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func test_markInboxMessageDeleted_givenNetworkError_expectCacheNotCleared() {
        let queueId = "queue-1"
        let expectation = XCTestExpectation(description: "Delete fails with error")

        // Setup: Cache has an entry
        inboxMessageCache.saveOpenedStatus(queueId: queueId, opened: false)
        XCTAssertNotNil(inboxMessageCache.getOpenedStatus(queueId: queueId))

        // Mock network error
        gistQueueNetworkMock.requestClosure = { _, _, completionHandler in
            completionHandler(.failure(GistNetworkError.requestFailed))
        }

        // When
        logManager.markInboxMessageDeleted(state: state, queueId: queueId) { result in
            switch result {
            case .success:
                XCTFail("Expected failure")
            case .failure:
                // Then: Cache should NOT be cleared
                XCTAssertNotNil(self.inboxMessageCache.getOpenedStatus(queueId: queueId))
                XCTAssertEqual(self.inboxMessageCache.getOpenedStatus(queueId: queueId), false)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Multiple Messages Tests

    func test_markInboxMessageDeleted_givenMultipleCachedMessages_expectOnlyTargetCleared() {
        let queueId1 = "queue-1"
        let queueId2 = "queue-2"
        let expectation = XCTestExpectation(description: "Delete one message")

        // Setup: Cache has multiple entries
        inboxMessageCache.saveOpenedStatus(queueId: queueId1, opened: true)
        inboxMessageCache.saveOpenedStatus(queueId: queueId2, opened: false)

        // Mock successful response
        gistQueueNetworkMock.requestClosure = { _, _, completionHandler in
            let response = HTTPURLResponse(
                url: URL(string: "https://test.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            completionHandler(.success((Data(), response)))
        }

        // When: Delete only queue-1
        logManager.markInboxMessageDeleted(state: state, queueId: queueId1) { result in
            switch result {
            case .success:
                // Then: Only queue-1 should be cleared
                XCTAssertNil(self.inboxMessageCache.getOpenedStatus(queueId: queueId1))
                XCTAssertEqual(self.inboxMessageCache.getOpenedStatus(queueId: queueId2), false)
                expectation.fulfill()
            case .failure:
                XCTFail("Expected success")
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }
}
