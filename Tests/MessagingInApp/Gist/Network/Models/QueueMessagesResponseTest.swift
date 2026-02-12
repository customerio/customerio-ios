@testable import CioMessagingInApp
import Foundation
import Testing

@Suite("QueueMessagesResponse Tests")
struct QueueMessagesResponseTest {
    @Test("Parses inAppMessages array")
    func parsesInAppMessagesArray() {
        let dictionary: [String: Any?] = [
            "inAppMessages": [
                [
                    "queueId": "in-app-1",
                    "priority": 5,
                    "messageId": "msg-1",
                    "properties": ["key": "value"]
                ],
                [
                    "queueId": "in-app-2",
                    "priority": 3,
                    "messageId": "msg-2",
                    "properties": nil
                ]
            ]
        ]

        let response = QueueMessagesResponse(dictionary: dictionary)

        #expect(response.inAppMessages.count == 2)
        #expect(response.inAppMessages[0].queueId == "in-app-1")
        #expect(response.inAppMessages[0].priority == 5)
        #expect(response.inAppMessages[0].messageId == "msg-1")
        #expect(response.inAppMessages[1].queueId == "in-app-2")
        #expect(response.inAppMessages[1].priority == 3)
    }

    @Test("Parses inboxMessages array")
    func parsesInboxMessagesArray() {
        let dictionary: [String: Any?] = [
            "inboxMessages": [
                [
                    "queueId": "inbox-1",
                    "deliveryId": "delivery-1",
                    "sentAt": "2026-02-09T12:26:42.513994Z",
                    "topics": ["promo"],
                    "type": "in-app",
                    "opened": false,
                    "priority": 5,
                    "properties": ["key": "value"]
                ],
                [
                    "queueId": "inbox-2",
                    "deliveryId": "delivery-2",
                    "sentAt": "2026-02-10T10:00:00Z",
                    "topics": nil,
                    "type": "email",
                    "opened": true,
                    "priority": 3,
                    "properties": nil
                ]
            ]
        ]

        let response = QueueMessagesResponse(dictionary: dictionary)

        #expect(response.inboxMessages.count == 2)
        #expect(response.inboxMessages[0].queueId == "inbox-1")
        #expect(response.inboxMessages[0].deliveryId == "delivery-1")
        #expect(response.inboxMessages[0].opened == false)
        #expect(response.inboxMessages[1].queueId == "inbox-2")
        #expect(response.inboxMessages[1].opened == true)
    }

    @Test("Handles empty and missing arrays with empty defaults")
    func handlesEmptyAndMissingArraysWithEmptyDefaults() {
        // Test with empty arrays
        let emptyArrays: [String: Any?] = [
            "inAppMessages": [],
            "inboxMessages": []
        ]
        let response1 = QueueMessagesResponse(dictionary: emptyArrays)
        #expect(response1.inAppMessages.isEmpty == true)
        #expect(response1.inboxMessages.isEmpty == true)

        // Test with missing arrays
        let missingArrays: [String: Any?] = [:]
        let response2 = QueueMessagesResponse(dictionary: missingArrays)
        #expect(response2.inAppMessages.isEmpty == true)
        #expect(response2.inboxMessages.isEmpty == true)
    }

    @Test("Filters out invalid inAppMessages")
    func filtersOutInvalidInAppMessages() {
        let dictionary: [String: Any?] = [
            "inAppMessages": [
                [
                    "queueId": "valid-1",
                    "priority": 5,
                    "messageId": "msg-1"
                ],
                [
                    // Missing required fields - should be filtered out
                    "priority": 3
                ],
                [
                    "queueId": "valid-2",
                    "priority": 2,
                    "messageId": "msg-2"
                ]
            ],
            "inboxMessages": []
        ]

        let response = QueueMessagesResponse(dictionary: dictionary)

        #expect(response.inAppMessages.count == 2)
        #expect(response.inAppMessages[0].queueId == "valid-1")
        #expect(response.inAppMessages[1].queueId == "valid-2")
    }
}
