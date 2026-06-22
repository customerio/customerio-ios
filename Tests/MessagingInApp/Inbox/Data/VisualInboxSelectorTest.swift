@testable import CioMessagingInApp
import Foundation
import XCTest

class VisualInboxSelectorTest: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10000)

    private func message(
        queueId: String,
        topics: [String],
        priority: Int? = nil,
        sentAt: Date = Date(timeIntervalSince1970: 5000),
        expiry: Date? = nil
    ) -> InboxMessage {
        InboxMessage(
            queueId: queueId,
            deliveryId: "d-\(queueId)",
            expiry: expiry,
            sentAt: sentAt,
            topics: topics,
            type: "card",
            opened: false,
            priority: priority,
            properties: [:]
        )
    }

    // MARK: - Prefix filter

    func test_select_whenTopicHasCioInboxPrefix_expectIncluded() {
        let included = message(queueId: "1", topics: ["cio_inbox_promos"])
        let excluded = message(queueId: "2", topics: ["promos"])

        let result = VisualInboxSelector.select(messages: [included, excluded], now: now)

        XCTAssertEqual(result.map(\.queueId), ["1"])
    }

    func test_select_whenTopicIsExactCioInboxPrefix_expectIncluded() {
        let exact = message(queueId: "1", topics: ["cio_inbox"])

        let result = VisualInboxSelector.select(messages: [exact], now: now)

        XCTAssertEqual(result.map(\.queueId), ["1"])
    }

    func test_select_whenPrefixDiffersByCase_expectIncluded() {
        let mixedCase = message(queueId: "1", topics: ["CIO_Inbox_News"])

        let result = VisualInboxSelector.select(messages: [mixedCase], now: now)

        XCTAssertEqual(result.map(\.queueId), ["1"])
    }

    func test_select_whenNoTopicMatchesPrefix_expectEmpty() {
        let m1 = message(queueId: "1", topics: ["inbox"]) // missing cio_ prefix
        let m2 = message(queueId: "2", topics: [])

        let result = VisualInboxSelector.select(messages: [m1, m2], now: now)

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Sort: priority asc -> sentAt desc

    func test_select_expectSortedByPriorityAscending() {
        let high = message(queueId: "high", topics: ["cio_inbox"], priority: 1)
        let low = message(queueId: "low", topics: ["cio_inbox"], priority: 100)
        let mid = message(queueId: "mid", topics: ["cio_inbox"], priority: 50)

        let result = VisualInboxSelector.select(messages: [low, high, mid], now: now)

        XCTAssertEqual(result.map(\.queueId), ["high", "mid", "low"])
    }

    func test_select_whenSamePriority_expectSortedBySentAtDescending() {
        let older = message(queueId: "older", topics: ["cio_inbox"], priority: 5, sentAt: Date(timeIntervalSince1970: 1000))
        let newer = message(queueId: "newer", topics: ["cio_inbox"], priority: 5, sentAt: Date(timeIntervalSince1970: 2000))

        let result = VisualInboxSelector.select(messages: [older, newer], now: now)

        XCTAssertEqual(result.map(\.queueId), ["newer", "older"])
    }

    func test_select_whenPriorityNil_expectSortedAfterPrioritized() {
        let prioritized = message(queueId: "p", topics: ["cio_inbox"], priority: 10)
        let noPriorityNew = message(queueId: "np-new", topics: ["cio_inbox"], priority: nil, sentAt: Date(timeIntervalSince1970: 3000))
        let noPriorityOld = message(queueId: "np-old", topics: ["cio_inbox"], priority: nil, sentAt: Date(timeIntervalSince1970: 1000))

        let result = VisualInboxSelector.select(messages: [noPriorityOld, noPriorityNew, prioritized], now: now)

        // prioritized first, then nil-priority by sentAt desc
        XCTAssertEqual(result.map(\.queueId), ["p", "np-new", "np-old"])
    }

    // MARK: - Expiry drop

    func test_select_whenExpiryInPast_expectDropped() {
        let expired = message(queueId: "exp", topics: ["cio_inbox"], expiry: Date(timeIntervalSince1970: 9999))
        let valid = message(queueId: "ok", topics: ["cio_inbox"], expiry: Date(timeIntervalSince1970: 20000))

        let result = VisualInboxSelector.select(messages: [expired, valid], now: now)

        XCTAssertEqual(result.map(\.queueId), ["ok"])
    }

    func test_select_whenExpiryEqualsNow_expectDropped() {
        let atNow = message(queueId: "atNow", topics: ["cio_inbox"], expiry: now)

        let result = VisualInboxSelector.select(messages: [atNow], now: now)

        XCTAssertTrue(result.isEmpty)
    }

    func test_select_whenNoExpiry_expectKept() {
        let m = message(queueId: "1", topics: ["cio_inbox"], expiry: nil)

        let result = VisualInboxSelector.select(messages: [m], now: now)

        XCTAssertEqual(result.map(\.queueId), ["1"])
    }
}
