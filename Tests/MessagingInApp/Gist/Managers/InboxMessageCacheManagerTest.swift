@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

class InboxMessageCacheManagerTest: UnitTest {
    private var cache: InboxMessageCacheManager!
    private var keyValueStorage: SharedKeyValueStorage!

    override func setUp() {
        super.setUp()

        keyValueStorage = diGraphShared.sharedKeyValueStorage
        cache = InboxMessageCacheManager(
            keyValueStore: keyValueStorage,
            logger: log
        )
    }

    // MARK: - getOpenedStatus Tests

    func test_getOpenedStatus_givenNoCachedData_expectNil() {
        let result = cache.getOpenedStatus(queueId: "queue-1")

        XCTAssertNil(result)
    }

    func test_getOpenedStatus_givenCachedData_expectCorrectValue() {
        cache.saveOpenedStatus(queueId: "queue-1", opened: true)
        cache.saveOpenedStatus(queueId: "queue-2", opened: false)

        let result1 = cache.getOpenedStatus(queueId: "queue-1")
        let result2 = cache.getOpenedStatus(queueId: "queue-2")

        XCTAssertEqual(result1, true)
        XCTAssertEqual(result2, false)
    }

    func test_getOpenedStatus_givenQueueIdNotInCache_expectNil() {
        cache.saveOpenedStatus(queueId: "queue-1", opened: true)

        let result = cache.getOpenedStatus(queueId: "queue-2")

        XCTAssertNil(result)
    }

    func test_getOpenedStatus_givenInvalidJSON_expectNil() {
        keyValueStorage.setData(Data("invalid json".utf8), forKey: .inboxMessagesOpenedStatus)

        let result = cache.getOpenedStatus(queueId: "queue-1")

        XCTAssertNil(result)
    }

    // MARK: - saveOpenedStatus Tests

    func test_saveOpenedStatus_givenNoExistingCache_expectNewCacheCreated() {
        cache.saveOpenedStatus(queueId: "queue-1", opened: true)

        let result = cache.getOpenedStatus(queueId: "queue-1")
        XCTAssertEqual(result, true)
    }

    func test_saveOpenedStatus_givenExistingCache_expectCacheUpdated() {
        cache.saveOpenedStatus(queueId: "queue-1", opened: false)
        cache.saveOpenedStatus(queueId: "queue-2", opened: true)

        cache.saveOpenedStatus(queueId: "queue-1", opened: true)

        let result1 = cache.getOpenedStatus(queueId: "queue-1")
        let result2 = cache.getOpenedStatus(queueId: "queue-2")
        XCTAssertEqual(result1, true)
        XCTAssertEqual(result2, true)
    }

    func test_saveOpenedStatus_givenMultipleMessages_expectAllSaved() {
        cache.saveOpenedStatus(queueId: "queue-1", opened: true)
        cache.saveOpenedStatus(queueId: "queue-2", opened: false)
        cache.saveOpenedStatus(queueId: "queue-3", opened: true)

        XCTAssertEqual(cache.getOpenedStatus(queueId: "queue-1"), true)
        XCTAssertEqual(cache.getOpenedStatus(queueId: "queue-2"), false)
        XCTAssertEqual(cache.getOpenedStatus(queueId: "queue-3"), true)
    }

    func test_saveOpenedStatus_givenSameQueueIdMultipleTimes_expectLatestValue() {
        cache.saveOpenedStatus(queueId: "queue-1", opened: true)
        cache.saveOpenedStatus(queueId: "queue-1", opened: false)
        cache.saveOpenedStatus(queueId: "queue-1", opened: true)

        let result = cache.getOpenedStatus(queueId: "queue-1")
        XCTAssertEqual(result, true)
    }

    func test_saveOpenedStatus_givenInvalidExistingCache_expectNewCacheCreated() {
        keyValueStorage.setData(Data("invalid json".utf8), forKey: .inboxMessagesOpenedStatus)

        cache.saveOpenedStatus(queueId: "queue-1", opened: true)

        let result = cache.getOpenedStatus(queueId: "queue-1")
        XCTAssertEqual(result, true)
    }

    // MARK: - clearOpenedStatus Tests

    func test_clearOpenedStatus_givenExistingEntry_expectEntryRemoved() {
        cache.saveOpenedStatus(queueId: "queue-1", opened: true)
        cache.saveOpenedStatus(queueId: "queue-2", opened: false)

        cache.clearOpenedStatus(queueId: "queue-1")

        XCTAssertNil(cache.getOpenedStatus(queueId: "queue-1"))
        XCTAssertEqual(cache.getOpenedStatus(queueId: "queue-2"), false)
    }

    func test_clearOpenedStatus_givenNonExistentEntry_expectNoChange() {
        cache.saveOpenedStatus(queueId: "queue-1", opened: true)

        cache.clearOpenedStatus(queueId: "queue-2")

        XCTAssertEqual(cache.getOpenedStatus(queueId: "queue-1"), true)
        XCTAssertNil(cache.getOpenedStatus(queueId: "queue-2"))
    }

    func test_clearOpenedStatus_givenNoCachedData_expectNil() {
        cache.clearOpenedStatus(queueId: "queue-1")

        XCTAssertNil(cache.getOpenedStatus(queueId: "queue-1"))
    }

    func test_clearOpenedStatus_givenInvalidCache_expectNil() {
        keyValueStorage.setData(Data("invalid json".utf8), forKey: .inboxMessagesOpenedStatus)

        cache.clearOpenedStatus(queueId: "queue-1")

        XCTAssertNil(cache.getOpenedStatus(queueId: "queue-1"))
    }

    // MARK: - Thread Safety Tests

    func test_concurrentAccess_givenMultipleThreads_expectNoDataCorruption() {
        let expectation = XCTestExpectation(description: "All concurrent operations complete")
        expectation.expectedFulfillmentCount = 30

        let queue1 = DispatchQueue(label: "test.queue1")
        let queue2 = DispatchQueue(label: "test.queue2")
        let queue3 = DispatchQueue(label: "test.queue3")

        // Simulate concurrent saves from different threads
        for i in 1 ... 10 {
            queue1.async {
                self.cache.saveOpenedStatus(queueId: "queue-\(i)", opened: true)
                expectation.fulfill()
            }
            queue2.async {
                self.cache.saveOpenedStatus(queueId: "queue-\(i + 10)", opened: false)
                expectation.fulfill()
            }
            queue3.async {
                _ = self.cache.getOpenedStatus(queueId: "queue-\(i)")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)

        // Verify data integrity - all 20 entries should be saved
        for i in 1 ... 10 {
            XCTAssertEqual(cache.getOpenedStatus(queueId: "queue-\(i)"), true)
        }
        for i in 11 ... 20 {
            XCTAssertEqual(cache.getOpenedStatus(queueId: "queue-\(i)"), false)
        }
    }

    func test_concurrentSaveAndClear_givenSameQueueId_expectNoRaceCondition() {
        let expectation = XCTestExpectation(description: "All operations complete")
        expectation.expectedFulfillmentCount = 100

        let queueId = "test-queue"

        // Rapidly save and clear from multiple threads
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            if Bool.random() {
                self.cache.saveOpenedStatus(queueId: queueId, opened: Bool.random())
            } else {
                self.cache.clearOpenedStatus(queueId: queueId)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        // Should not crash - data may or may not exist depending on timing
        // but the cache should remain valid (no exception thrown)
        _ = cache.getOpenedStatus(queueId: queueId)
    }

    // MARK: - Storage Integration Tests

    func test_saveAndRetrieve_expectDataPersisted() {
        cache.saveOpenedStatus(queueId: "queue-1", opened: true)

        guard let data = keyValueStorage.data(.inboxMessagesOpenedStatus) else {
            XCTFail("Expected data to be saved")
            return
        }

        guard let dict = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            XCTFail("Expected valid JSON data")
            return
        }
        XCTAssertEqual(dict["queue-1"], true)
    }

    func test_clearOpenedStatus_expectDataRemovedFromStorage() {
        cache.saveOpenedStatus(queueId: "queue-1", opened: true)
        cache.saveOpenedStatus(queueId: "queue-2", opened: false)

        cache.clearOpenedStatus(queueId: "queue-1")

        guard let data = keyValueStorage.data(.inboxMessagesOpenedStatus) else {
            XCTFail("Expected data to be saved")
            return
        }

        guard let dict = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            XCTFail("Expected valid JSON data")
            return
        }
        XCTAssertNil(dict["queue-1"])
        XCTAssertEqual(dict["queue-2"], false)
    }

    // MARK: - Clear All Tests

    func test_clearAll_givenCachedData_expectAllCleared() {
        cache.saveOpenedStatus(queueId: "queue-1", opened: true)
        cache.saveOpenedStatus(queueId: "queue-2", opened: false)
        cache.saveOpenedStatus(queueId: "queue-3", opened: true)

        cache.clearAll()

        XCTAssertNil(cache.getOpenedStatus(queueId: "queue-1"))
        XCTAssertNil(cache.getOpenedStatus(queueId: "queue-2"))
        XCTAssertNil(cache.getOpenedStatus(queueId: "queue-3"))

        let data = keyValueStorage.data(.inboxMessagesOpenedStatus)
        XCTAssertNil(data)
    }

    func test_clearAll_givenNoCachedData_expectNoError() {
        cache.clearAll()

        XCTAssertNil(cache.getOpenedStatus(queueId: "queue-1"))
        let data = keyValueStorage.data(.inboxMessagesOpenedStatus)
        XCTAssertNil(data)
    }
}
