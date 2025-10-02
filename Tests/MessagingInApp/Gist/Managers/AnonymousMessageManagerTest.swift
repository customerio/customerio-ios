@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

class AnonymousMessageManagerTest: UnitTest {
    private var manager: AnonymousMessageManagerImpl!

    override func setUp() {
        super.setUp()

        manager = AnonymousMessageManagerImpl(
            keyValueStorage: diGraphShared.sharedKeyValueStorage,
            dateUtil: dateUtilStub,
            logger: diGraphShared.logger
        )
    }

    // MARK: - Cleanup Bug Fix Tests

    func test_cleanup_cacheExpiry_expectTrackingDataCleared() {
        // Given: Message with tracking data
        let message = createAnonymousMessage(messageId: "expiry-test", count: 5, delay: 10)
        manager.updateAnonymousMessagesLocalStore(messages: [message])
        manager.markAnonymousAsSeen(messageId: "expiry-test")
        manager.markAnonymousAsDismissed(messageId: "expiry-test")

        // Verify tracking exists
        let trackingBefore = diGraphShared.sharedKeyValueStorage.string(.broadcastMessagesTracking)
        XCTAssertNotNil(trackingBefore)
        XCTAssertTrue(trackingBefore!.contains("expiry-test"))

        // When: Cache expires (61 minutes pass)
        let sixtyOneMinutesLater = dateUtilStub.givenNow.addingTimeInterval(61 * 60)
        dateUtilStub.givenNow = sixtyOneMinutesLater

        // Get eligible messages (triggers cleanup)
        let eligible = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligible.count, 0)

        // Then: Tracking data should be cleared
        let trackingAfter = diGraphShared.sharedKeyValueStorage.string(.broadcastMessagesTracking)
        if let trackingJson = trackingAfter,
           let data = trackingJson.data(using: .utf8),
           let tracking = try? JSONDecoder().decode(MessagesTrackingData.self, from: data) {
            XCTAssertFalse(tracking.tracking.keys.contains("expiry-test"), "Tracking should be cleared on expiry")
        }
    }

    func test_cleanup_idReusePrevention_expectCleanState() {
        // This test verifies the critical bug fix:
        // When messages are cleared and then reintroduced with same ID,
        // they should not inherit stale tracking state

        // Given: Message "reused-id" is shown and dismissed
        let message1 = createAnonymousMessage(messageId: "reused-id", count: 5, delay: 0)
        manager.updateAnonymousMessagesLocalStore(messages: [message1])
        manager.markAnonymousAsSeen(messageId: "reused-id")
        manager.markAnonymousAsDismissed(messageId: "reused-id")

        // When: Server clears all anonymous messages
        manager.updateAnonymousMessagesLocalStore(messages: [])

        // Then: Later, same ID is reintroduced
        let message2 = createAnonymousMessage(messageId: "reused-id", count: 5, delay: 0)
        manager.updateAnonymousMessagesLocalStore(messages: [message2])

        // The reused message should be eligible (not dismissed from previous state)
        let eligible = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligible.count, 1, "Reused ID should start with clean state")
        XCTAssertEqual(eligible.first?.messageId, "reused-id")
    }

    // MARK: - Bug Fix: Messages with nil queueId/priority

    func test_bugFix_anonymousMessagesWithNilQueueId_expectNotDropped() {
        // This test verifies the critical bug fix where anonymous messages with nil queueId
        // were being dropped during UserQueueResponse conversion in processAnonymousMessages

        // Given: Anonymous message with nil queueId (can happen from local storage)
        let properties: [String: Any] = [
            "gist": [
                "broadcast": [
                    "frequency": [
                        "count": 0, // unlimited
                        "delay": 0,
                        "ignoreDismiss": false
                    ]
                ]
            ]
        ]

        let messageWithNilQueueId = Message(
            messageId: "msg-nil-queueid",
            queueId: nil, // Explicitly nil
            priority: 1,
            properties: properties
        )

        // When: Update local store with this message
        manager.updateAnonymousMessagesLocalStore(messages: [messageWithNilQueueId])

        // Then: Message should still be eligible (not dropped)
        let eligible = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligible.count, 1, "Message with nil queueId should not be dropped")
        XCTAssertEqual(eligible.first?.messageId, "msg-nil-queueid")
        XCTAssertNil(eligible.first?.queueId, "queueId should remain nil")
    }

    func test_bugFix_anonymousMessagesWithNilPriority_expectNotDropped() {
        // This test verifies anonymous messages with nil priority are processed correctly

        // Given: Anonymous message with nil priority
        let properties: [String: Any] = [
            "gist": [
                "broadcast": [
                    "frequency": [
                        "count": 5,
                        "delay": 0,
                        "ignoreDismiss": false
                    ]
                ]
            ]
        ]

        let messageWithNilPriority = Message(
            messageId: "msg-nil-priority",
            queueId: "queue-123",
            priority: nil, // Explicitly nil
            properties: properties
        )

        // When: Update local store with this message
        manager.updateAnonymousMessagesLocalStore(messages: [messageWithNilPriority])

        // Then: Message should still be eligible (not dropped)
        let eligible = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligible.count, 1, "Message with nil priority should not be dropped")
        XCTAssertEqual(eligible.first?.messageId, "msg-nil-priority")
        XCTAssertNil(eligible.first?.priority, "priority should remain nil")
    }

    // MARK: - Message Parsing Tests

    func test_parseBroadcastProperties_givenValidFrequency_expectCorrectParsing() {
        let properties: [String: Any] = [
            "gist": [
                "broadcast": [
                    "frequency": [
                        "count": 3,
                        "delay": 60,
                        "ignoreDismiss": true
                    ]
                ]
            ]
        ]

        let message = Message(messageId: "test-msg", properties: properties)

        XCTAssertNotNil(message.gistProperties.broadcast)
        XCTAssertEqual(message.gistProperties.broadcast?.frequency.count, 3)
        XCTAssertEqual(message.gistProperties.broadcast?.frequency.delay, 60)
        XCTAssertEqual(message.gistProperties.broadcast?.frequency.ignoreDismiss, true)
        XCTAssertTrue(message.isAnonymousMessage)
    }

    func test_parseBroadcastProperties_givenNoBroadcast_expectNil() {
        let properties: [String: Any] = [
            "gist": [:]
        ]

        let message = Message(messageId: "test-msg", properties: properties)

        XCTAssertNil(message.gistProperties.broadcast)
        XCTAssertFalse(message.isAnonymousMessage)
    }

    func test_parseBroadcastProperties_givenMissingCountDelay_expectNil() {
        let properties: [String: Any] = [
            "gist": [
                "broadcast": [
                    "frequency": [:]
                ]
            ]
        ]

        let message = Message(messageId: "test-msg", properties: properties)

        // When count/delay are missing, broadcast should be nil
        XCTAssertNil(message.gistProperties.broadcast)
        XCTAssertFalse(message.isAnonymousMessage)
    }

    // MARK: - Frequency Control Tests

    func test_frequencyControl_unlimitedShows_count0_expectAlwaysEligible() {
        // Given: Message with count=0 (unlimited)
        let message = createAnonymousMessage(messageId: "unlimited-msg", count: 0, delay: 0)
        storeMessages([message])

        // When: Message is shown multiple times
        manager.markAnonymousAsSeen(messageId: "unlimited-msg")
        manager.markAnonymousAsSeen(messageId: "unlimited-msg")
        manager.markAnonymousAsSeen(messageId: "unlimited-msg")
        manager.markAnonymousAsSeen(messageId: "unlimited-msg")
        manager.markAnonymousAsSeen(messageId: "unlimited-msg")

        // Then: Should still be eligible
        let eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 1)
        XCTAssertEqual(eligibleMessages.first?.messageId, "unlimited-msg")
    }

    func test_frequencyControl_singleShow_count1_expectOnlyEligibleOnce() {
        // Given: Message with count=1 (show once)
        let message = createAnonymousMessage(messageId: "once-msg", count: 1, delay: 0)
        storeMessages([message])

        // When: Message has not been shown yet
        var eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 1)

        // When: Message is shown once
        manager.markAnonymousAsSeen(messageId: "once-msg")

        // Then: Should no longer be eligible
        eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 0)
    }

    func test_frequencyControl_limitedShows_count3_expectEligibleUntilLimit() {
        // Given: Message with count=3
        let message = createAnonymousMessage(messageId: "limited-msg", count: 3, delay: 0)
        storeMessages([message])

        // When: Message shown 0 times - eligible
        var eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 1)

        // When: Message shown 1 time - still eligible
        manager.markAnonymousAsSeen(messageId: "limited-msg")
        eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 1)

        // When: Message shown 2 times - still eligible
        manager.markAnonymousAsSeen(messageId: "limited-msg")
        eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 1)

        // When: Message shown 3 times - no longer eligible (reached limit)
        manager.markAnonymousAsSeen(messageId: "limited-msg")
        eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 0)
    }

    // MARK: - Delay Tests

    func test_delay_noDelay_expectImmediateEligibility() {
        // Given: Message with no delay
        let message = createAnonymousMessage(messageId: "nodelay-msg", count: 0, delay: 0)
        storeMessages([message])

        // When: Message is shown
        manager.markAnonymousAsSeen(messageId: "nodelay-msg")

        // Then: Should be immediately eligible again
        let eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 1)
    }

    func test_delay_30seconds_expectNotEligibleDuringDelayPeriod() {
        // Given: Message with 30 second delay
        let message = createAnonymousMessage(messageId: "delay-msg", count: 0, delay: 30)
        storeMessages([message])
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 1000) // Set current time

        // When: Message is shown
        manager.markAnonymousAsSeen(messageId: "delay-msg")

        // Then: Should NOT be eligible during delay period
        var eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 0)

        // When: Time advances by 20 seconds (still in delay period)
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 1020)
        eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 0)

        // When: Time advances by 30+ seconds (delay period expired)
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 1031)
        eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 1)
    }

    func test_delay_longDelay_expectCorrectCalculation() {
        // Given: Message with 3600 second (1 hour) delay
        let message = createAnonymousMessage(messageId: "longdelay-msg", count: 0, delay: 3600)
        storeMessages([message])
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 10000)

        // When: Message is shown
        manager.markAnonymousAsSeen(messageId: "longdelay-msg")

        // Then: Should not be eligible for 1 hour
        var eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 0)

        // When: 59 minutes pass (still in delay)
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 10000 + 3540)
        eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 0)

        // When: 1 hour+ passes
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 10000 + 3601)
        eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 1)
    }

    // MARK: - Dismiss Tests

    func test_dismiss_respectDismiss_expectNotEligibleAfterDismiss() {
        // Given: Message with ignoreDismiss=false (respect dismissal)
        let message = createAnonymousMessage(messageId: "dismiss-msg", count: 0, delay: 0, ignoreDismiss: false)
        storeMessages([message])

        // When: Message is eligible initially
        var eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 1)

        // When: User dismisses the message
        manager.markAnonymousAsDismissed(messageId: "dismiss-msg")

        // Then: Should no longer be eligible
        eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 0)
    }

    func test_dismiss_ignoreDismiss_expectStillEligibleAfterDismiss() {
        // Given: Message with ignoreDismiss=true
        let message = createAnonymousMessage(messageId: "ignore-msg", count: 0, delay: 0, ignoreDismiss: true)
        storeMessages([message])

        // When: Message is eligible initially
        var eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 1)

        // When: User dismisses the message
        manager.markAnonymousAsDismissed(messageId: "ignore-msg")

        // Then: Should STILL be eligible (ignoreDismiss flag)
        eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 1)
    }

    // MARK: - Expiry Tests

    func test_expiry_withinTTL_expectMessagesAvailable() {
        // Given: Messages stored with expiry in 60 minutes
        let message = createAnonymousMessage(messageId: "fresh-msg", count: 0, delay: 0)
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 1000)
        manager.updateAnonymousMessagesLocalStore(messages: [message])

        // When: 30 minutes pass (still within 60 min TTL)
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 1000 + 1800) // +30 min

        // Then: Messages should still be available
        let eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 1)
    }

    func test_expiry_pastTTL_expectMessagesExpired() {
        // Given: Messages stored at time 1000
        let message = createAnonymousMessage(messageId: "expired-msg", count: 0, delay: 0)
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 1000)
        manager.updateAnonymousMessagesLocalStore(messages: [message])

        // When: 61 minutes pass (past 60 min TTL)
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 1000 + 3660) // +61 min

        // Then: Messages should be expired
        let eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 0)
    }

    func test_expiry_exactlyAtTTL_expectMessagesExpired() {
        // Given: Messages stored at time 1000
        let message = createAnonymousMessage(messageId: "exact-msg", count: 0, delay: 0)
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 1000)
        manager.updateAnonymousMessagesLocalStore(messages: [message])

        // When: Exactly 60 minutes pass
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 1000 + 3600) // +60 min exactly

        // Then: Messages should be expired (>= check)
        let eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 0)
    }

    // MARK: - Combined Scenarios

    func test_combined_frequencyAndDelay_expectCorrectBehavior() {
        // Given: Message with count=2 and delay=10 seconds
        let message = createAnonymousMessage(messageId: "combo-msg", count: 2, delay: 10)
        storeMessages([message])
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 5000)

        // First show
        var eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 1, "Should be eligible for first show")

        manager.markAnonymousAsSeen(messageId: "combo-msg")

        // During delay period after first show
        eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 0, "Should not be eligible during delay period")

        // After delay period, before second show
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 5011)
        eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 1, "Should be eligible for second show after delay")

        // Second show
        manager.markAnonymousAsSeen(messageId: "combo-msg")

        // After reaching frequency limit
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 5022)
        eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 0, "Should not be eligible after reaching count limit")
    }

    func test_combined_dismissAndFrequency_expectDismissTakesPrecedence() {
        // Given: Message with count=5 but ignoreDismiss=false
        let message = createAnonymousMessage(messageId: "dismiss-freq-msg", count: 5, delay: 0, ignoreDismiss: false)
        storeMessages([message])

        // When: Message shown once then dismissed
        manager.markAnonymousAsSeen(messageId: "dismiss-freq-msg")
        manager.markAnonymousAsDismissed(messageId: "dismiss-freq-msg")

        // Then: Should not be eligible even though frequency limit not reached
        let eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 0)
    }

    func test_combined_allFlags_complexScenario() {
        // Given: Message with count=3, delay=5, ignoreDismiss=true
        let message = createAnonymousMessage(messageId: "complex-msg", count: 3, delay: 5, ignoreDismiss: true)
        storeMessages([message])
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 8000)

        // Show 1
        manager.markAnonymousAsSeen(messageId: "complex-msg")
        manager.markAnonymousAsDismissed(messageId: "complex-msg") // User dismisses

        // During delay - should not be eligible
        var eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 0)

        // After delay - should be eligible (ignoreDismiss=true)
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 8006)
        eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 1)

        // Show 2 and 3
        manager.markAnonymousAsSeen(messageId: "complex-msg")
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 8012)

        manager.markAnonymousAsSeen(messageId: "complex-msg")
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 8018)

        // After 3 shows - should not be eligible (reached frequency limit)
        eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 0)
    }

    // MARK: - Edge Cases

    func test_edgeCase_emptyMessageList_expectNoErrors() {
        // Given: No messages
        manager.updateAnonymousMessagesLocalStore(messages: [])

        // When: Getting eligible messages
        let eligibleMessages = manager.getEligibleAnonymousMessages()

        // Then: Should return empty array
        XCTAssertEqual(eligibleMessages.count, 0)
    }

    func test_edgeCase_multipleMessages_expectCorrectFiltering() {
        // Given: Multiple messages with different eligibility
        let eligible1 = createAnonymousMessage(messageId: "eligible-1", count: 0, delay: 0)
        let eligible2 = createAnonymousMessage(messageId: "eligible-2", count: 2, delay: 0)
        let notEligible1 = createAnonymousMessage(messageId: "not-eligible-1", count: 1, delay: 0)
        let notEligible2 = createAnonymousMessage(messageId: "not-eligible-2", count: 0, delay: 10)

        storeMessages([eligible1, eligible2, notEligible1, notEligible2])
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 2000)

        // Mark some as seen/dismissed
        manager.markAnonymousAsSeen(messageId: "not-eligible-1") // Reached limit (count=1)
        manager.markAnonymousAsSeen(messageId: "not-eligible-2") // In delay period

        // When: Getting eligible messages
        let eligibleMessages = manager.getEligibleAnonymousMessages()

        // Then: Only eligible ones returned
        XCTAssertEqual(eligibleMessages.count, 2)
        let eligibleIds = Set(eligibleMessages.map(\.messageId))
        XCTAssertTrue(eligibleIds.contains("eligible-1"))
        XCTAssertTrue(eligibleIds.contains("eligible-2"))
    }

    func test_edgeCase_cleanupRemovedMessages_expectTrackingCleared() {
        // Given: Initial messages with tracking data
        let message1 = createAnonymousMessage(messageId: "msg-1", count: 0, delay: 0)
        let message2 = createAnonymousMessage(messageId: "msg-2", count: 0, delay: 0)
        manager.updateAnonymousMessagesLocalStore(messages: [message1, message2])

        manager.markAnonymousAsSeen(messageId: "msg-1")
        manager.markAnonymousAsSeen(messageId: "msg-2")
        manager.markAnonymousAsDismissed(messageId: "msg-1")

        // Verify tracking exists by checking eligible messages
        var eligibleCount = manager.getEligibleAnonymousMessages().count
        XCTAssertGreaterThan(eligibleCount, 0)

        // When: Update with only msg-2 (msg-1 removed)
        manager.updateAnonymousMessagesLocalStore(messages: [message2])

        // Then: Only msg-2 should be available
        let eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 1)
        XCTAssertEqual(eligibleMessages.first?.messageId, "msg-2")
    }

    func test_edgeCase_noAnonymousMessages_expectClearAll() {
        // Given: Anonymous messages exist with tracking data
        let message = createAnonymousMessage(messageId: "temp-msg", count: 0, delay: 0)
        manager.updateAnonymousMessagesLocalStore(messages: [message])

        // Mark as seen to create tracking data
        manager.markAnonymousAsSeen(messageId: "temp-msg")

        // Verify tracking data exists
        let trackingDataBefore = diGraphShared.sharedKeyValueStorage.string(.broadcastMessagesTracking)
        XCTAssertNotNil(trackingDataBefore)
        XCTAssertTrue(trackingDataBefore!.contains("temp-msg"))

        // When: Server returns empty anonymous message list
        manager.updateAnonymousMessagesLocalStore(messages: [])

        // Then: All data should be cleared
        XCTAssertNil(diGraphShared.sharedKeyValueStorage.string(.broadcastMessages))
        XCTAssertNil(diGraphShared.sharedKeyValueStorage.double(.broadcastMessagesExpiry))

        let trackingDataAfter = diGraphShared.sharedKeyValueStorage.string(.broadcastMessagesTracking)
        if let trackingJson = trackingDataAfter,
           let data = trackingJson.data(using: .utf8),
           let tracking = try? JSONDecoder().decode(MessagesTrackingData.self, from: data) {
            XCTAssertFalse(tracking.tracking.keys.contains("temp-msg"), "Tracking data for temp-msg should be removed")
        }
    }

    func test_edgeCase_mixedAnonymousAndRegular_expectOnlyAnonymousStored() {
        // Given: Mix of anonymous and regular messages
        let anonymousMsg = createAnonymousMessage(messageId: "anon-msg", count: 0, delay: 0)
        let regularMsg = Message(messageId: "regular-msg", priority: 1, queueId: "queue-1")

        // When: Updating store
        manager.updateAnonymousMessagesLocalStore(messages: [anonymousMsg, regularMsg])

        // Then: Only anonymous message should be stored
        let eligibleMessages = manager.getEligibleAnonymousMessages()
        XCTAssertEqual(eligibleMessages.count, 1)
        XCTAssertEqual(eligibleMessages.first?.messageId, "anon-msg")
    }

    // MARK: - Helper Methods

    private func createAnonymousMessage(
        messageId: String,
        count: Int,
        delay: Int,
        ignoreDismiss: Bool = false
    ) -> Message {
        let properties: [String: Any] = [
            "gist": [
                "broadcast": [
                    "frequency": [
                        "count": count,
                        "delay": delay,
                        "ignoreDismiss": ignoreDismiss
                    ]
                ]
            ]
        ]

        return Message(
            messageId: messageId,
            queueId: "queue-\(messageId)",
            priority: 1,
            properties: properties
        )
    }

    private func storeMessages(_ messages: [Message]) {
        dateUtilStub.givenNow = Date()
        manager.updateAnonymousMessagesLocalStore(messages: messages)
    }

    // MARK: - Defensive Validation Tests

    func test_parseBroadcastProperties_givenNegativeCount_expectNil() {
        // Given: Message with negative count
        let properties: [String: Any] = [
            "gist": [
                "broadcast": [
                    "frequency": [
                        "count": -1,
                        "delay": 10
                    ]
                ]
            ]
        ]

        // When: Create message
        let message = Message(messageId: "test-msg", queueId: "queue-1", priority: 1, properties: properties)

        // Then: Should not parse as anonymous message
        XCTAssertFalse(message.isAnonymousMessage)
    }

    func test_parseBroadcastProperties_givenNegativeDelay_expectNil() {
        // Given: Message with negative delay
        let properties: [String: Any] = [
            "gist": [
                "broadcast": [
                    "frequency": [
                        "count": 3,
                        "delay": -10
                    ]
                ]
            ]
        ]

        // When: Create message
        let message = Message(messageId: "test-msg", queueId: "queue-1", priority: 1, properties: properties)

        // Then: Should not parse as anonymous message
        XCTAssertFalse(message.isAnonymousMessage)
    }
}
