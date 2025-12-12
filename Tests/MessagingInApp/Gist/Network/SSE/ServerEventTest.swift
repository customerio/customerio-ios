@testable import CioMessagingInApp
import XCTest

class ServerEventTest: XCTestCase {
    // MARK: - EventType Parsing

    func test_eventType_givenConnected_expectConnected() {
        let eventType = ServerEvent.EventType(rawValue: "connected")
        XCTAssertEqual(eventType, .connected)
    }

    func test_eventType_givenHeartbeat_expectHeartbeat() {
        let eventType = ServerEvent.EventType(rawValue: "heartbeat")
        XCTAssertEqual(eventType, .heartbeat)
    }

    func test_eventType_givenMessages_expectMessages() {
        let eventType = ServerEvent.EventType(rawValue: "messages")
        XCTAssertEqual(eventType, .messages)
    }

    func test_eventType_givenTtlExceeded_expectTtlExceeded() {
        let eventType = ServerEvent.EventType(rawValue: "ttl_exceeded")
        XCTAssertEqual(eventType, .ttlExceeded)
    }

    func test_eventType_givenEmptyString_expectMessages() {
        // Per SSE spec, empty/nil event type defaults to "message"
        let eventType = ServerEvent.EventType(rawValue: "")
        XCTAssertEqual(eventType, .messages)
    }

    func test_eventType_givenUnknownValue_expectUnknown() {
        let eventType = ServerEvent.EventType(rawValue: "some_future_event")
        XCTAssertEqual(eventType, .unknown)
    }

    func test_eventType_givenRandomString_expectUnknown() {
        let eventType = ServerEvent.EventType(rawValue: "xyz123")
        XCTAssertEqual(eventType, .unknown)
    }

    // MARK: - ServerEvent Initialization

    func test_serverEvent_givenConnectedType_expectConnectedEventType() {
        let event = ServerEvent(id: nil, type: "connected", data: "{}")
        XCTAssertEqual(event.eventType, .connected)
        XCTAssertEqual(event.rawEventType, "connected")
        XCTAssertNil(event.messages)
    }

    func test_serverEvent_givenNilType_expectMessagesEventType() {
        let event = ServerEvent(id: nil, type: nil, data: "[]")
        XCTAssertEqual(event.eventType, .messages)
        XCTAssertNil(event.rawEventType)
    }

    func test_serverEvent_givenEventId_expectIdPreserved() {
        let event = ServerEvent(id: "event-123", type: "heartbeat", data: "{}")
        XCTAssertEqual(event.id, "event-123")
    }

    // MARK: - Message Parsing - Valid Cases

    func test_parseMessages_givenValidJsonArray_expectMessages() {
        // UserQueueResponse requires: queueId (String), priority (Int), messageId (String)
        let jsonData = """
        [{"queueId": "q1", "priority": 1, "messageId": "m1"}, {"queueId": "q2", "priority": 2, "messageId": "m2"}]
        """
        let event = ServerEvent(id: nil, type: "messages", data: jsonData)

        XCTAssertNotNil(event.messages)
        XCTAssertEqual(event.messages?.count, 2)
    }

    func test_parseMessages_givenSingleMessage_expectOneMessage() {
        let jsonData = """
        [{"queueId": "q1", "priority": 1, "messageId": "m1"}]
        """
        let event = ServerEvent(id: nil, type: "messages", data: jsonData)

        XCTAssertNotNil(event.messages)
        XCTAssertEqual(event.messages?.count, 1)
    }

    // MARK: - Message Parsing - Empty/Nil Cases

    func test_parseMessages_givenEmptyArray_expectNil() {
        let event = ServerEvent(id: nil, type: "messages", data: "[]")
        XCTAssertNil(event.messages)
    }

    func test_parseMessages_givenEmptyString_expectNil() {
        let event = ServerEvent(id: nil, type: "messages", data: "")
        XCTAssertNil(event.messages)
    }

    func test_parseMessages_givenWhitespaceOnly_expectNil() {
        let event = ServerEvent(id: nil, type: "messages", data: "   ")
        XCTAssertNil(event.messages)
    }

    // MARK: - Message Parsing - Non-Message Event Types

    func test_parseMessages_givenConnectedType_expectNilMessages() {
        // Even with valid message JSON, non-message event types should not parse messages
        let jsonData = """
        [{"queueId": "q1", "priority": 1, "messageId": "m1"}]
        """
        let event = ServerEvent(id: nil, type: "connected", data: jsonData)

        // Should not parse messages for non-message event types
        XCTAssertNil(event.messages)
    }

    func test_parseMessages_givenHeartbeatType_expectNilMessages() {
        let event = ServerEvent(id: nil, type: "heartbeat", data: "{}")
        XCTAssertNil(event.messages)
    }

    func test_parseMessages_givenUnknownType_expectNilMessages() {
        let jsonData = """
        [{"queueId": "q1", "priority": 1, "messageId": "m1"}]
        """
        let event = ServerEvent(id: nil, type: "future_event", data: jsonData)
        XCTAssertNil(event.messages)
    }

    // MARK: - Message Parsing - Malformed JSON (Resilience Tests)

    func test_parseMessages_givenInvalidJson_expectNil() {
        let event = ServerEvent(id: nil, type: "messages", data: "not json at all")
        XCTAssertNil(event.messages)
    }

    func test_parseMessages_givenMalformedJson_expectNil() {
        let event = ServerEvent(id: nil, type: "messages", data: "{invalid json}")
        XCTAssertNil(event.messages)
    }

    func test_parseMessages_givenJsonObject_expectNil() {
        // JSON object instead of array
        let event = ServerEvent(id: nil, type: "messages", data: "{\"key\": \"value\"}")
        XCTAssertNil(event.messages)
    }

    func test_parseMessages_givenJsonString_expectNil() {
        // JSON string instead of array
        let event = ServerEvent(id: nil, type: "messages", data: "\"just a string\"")
        XCTAssertNil(event.messages)
    }

    func test_parseMessages_givenJsonNumber_expectNil() {
        // JSON number instead of array
        let event = ServerEvent(id: nil, type: "messages", data: "12345")
        XCTAssertNil(event.messages)
    }

    func test_parseMessages_givenArrayOfStrings_expectNil() {
        // Array of strings instead of objects
        let event = ServerEvent(id: nil, type: "messages", data: "[\"a\", \"b\", \"c\"]")
        XCTAssertNil(event.messages)
    }

    func test_parseMessages_givenArrayOfNumbers_expectNil() {
        // Array of numbers instead of objects
        let event = ServerEvent(id: nil, type: "messages", data: "[1, 2, 3]")
        XCTAssertNil(event.messages)
    }

    // MARK: - Message Parsing - Partial Validity

    func test_parseMessages_givenMixedValidAndInvalidItems_expectOnlyValidMessages() {
        // Array with some valid and some invalid items
        // Valid items have: queueId, priority, messageId
        // Invalid item is missing required fields
        let jsonData = """
        [{"queueId": "q1", "priority": 1, "messageId": "m1"}, {"invalid": "item"}, {"queueId": "q2", "priority": 2, "messageId": "m2"}]
        """
        let event = ServerEvent(id: nil, type: "messages", data: jsonData)

        // Should parse valid items (2) and skip invalid one (1)
        XCTAssertNotNil(event.messages)
        XCTAssertEqual(event.messages?.count, 2)
    }

    // MARK: - SseEvent Equatable

    func test_sseEvent_connectionOpen_equatable() {
        let event1 = SseEvent.connectionOpen
        let event2 = SseEvent.connectionOpen
        XCTAssertEqual(event1, event2)
    }

    func test_sseEvent_connectionClosed_equatable() {
        let event1 = SseEvent.connectionClosed
        let event2 = SseEvent.connectionClosed
        XCTAssertEqual(event1, event2)
    }

    func test_sseEvent_serverEvent_equatable() {
        let serverEvent1 = ServerEvent(id: "1", type: "connected", data: "{}")
        let serverEvent2 = ServerEvent(id: "1", type: "connected", data: "{}")
        XCTAssertEqual(SseEvent.serverEvent(serverEvent1), SseEvent.serverEvent(serverEvent2))
    }

    func test_sseEvent_connectionFailed_equatable() {
        let error1 = SseError(message: "error")
        let error2 = SseError(message: "error")
        XCTAssertEqual(SseEvent.connectionFailed(error1), SseEvent.connectionFailed(error2))
    }

    // MARK: - SseError

    func test_sseError_givenSameMessage_expectEqual() {
        let error1 = SseError(message: "Connection failed")
        let error2 = SseError(message: "Connection failed")
        XCTAssertEqual(error1, error2)
    }

    func test_sseError_givenDifferentMessage_expectNotEqual() {
        let error1 = SseError(message: "Error 1")
        let error2 = SseError(message: "Error 2")
        XCTAssertNotEqual(error1, error2)
    }

    func test_sseError_givenUnderlyingError_expectMessagePreserved() {
        let underlyingError = NSError(domain: "test", code: 123)
        let sseError = SseError(message: "Wrapper error", underlyingError: underlyingError)

        XCTAssertEqual(sseError.message, "Wrapper error")
        XCTAssertNotNil(sseError.underlyingError)
    }
}
