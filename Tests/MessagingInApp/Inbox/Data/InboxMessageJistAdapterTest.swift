@testable import CioMessagingInApp
import Foundation
import XCTest

class InboxMessageJistAdapterTest: XCTestCase {
    private func message(properties: [String: Any]) -> InboxMessage {
        InboxMessage(
            queueId: "q1",
            deliveryId: "d1",
            expiry: nil,
            sentAt: Date(timeIntervalSince1970: 1000),
            topics: ["cio_inbox"],
            type: "card",
            opened: true,
            priority: 3,
            properties: properties
        )
    }

    func test_toJist_expectScalarFieldsCarriedThrough() {
        let jist = InboxMessageJistAdapter.toJist(message(properties: [:]))

        XCTAssertEqual(jist.queueId, "q1")
        XCTAssertEqual(jist.type, "card")
        XCTAssertTrue(jist.opened)
        XCTAssertEqual(jist.priority, 3)
        XCTAssertEqual(jist.sentAt, Date(timeIntervalSince1970: 1000))
    }

    func test_toJist_expectNestedObjectPreservedNotFlattened() {
        let nested: [String: Any] = [
            "cta": [
                "label": "Open",
                "url": "https://example.com",
                "enabled": true
            ]
        ]
        let jist = InboxMessageJistAdapter.toJist(message(properties: nested))

        let cta = jist.properties["cta"] as? [String: Any]
        XCTAssertNotNil(cta, "Nested object must remain a dictionary, not a flattened string")
        XCTAssertEqual(cta?["label"] as? String, "Open")
        XCTAssertEqual(cta?["enabled"] as? Bool, true)
    }

    func test_toJist_expectArrayPreserved() {
        let props: [String: Any] = ["tags": ["a", "b", "c"]]
        let jist = InboxMessageJistAdapter.toJist(message(properties: props))

        let tags = jist.properties["tags"] as? [String]
        XCTAssertEqual(tags, ["a", "b", "c"])
    }

    func test_toJist_expectBoolNotCoercedToString() {
        let props: [String: Any] = ["featured": true, "count": 0]
        let jist = InboxMessageJistAdapter.toJist(message(properties: props))

        // Bool must stay Bool (NSNumber bridging would let "true" parse as 1; assert type explicitly).
        XCTAssertEqual(jist.properties["featured"] as? Bool, true)
        XCTAssertNil(jist.properties["featured"] as? String)
    }

    func test_toJist_expectNumbersPreservedAsNumbers() {
        let props: [String: Any] = ["int": 42, "double": 3.14]
        let jist = InboxMessageJistAdapter.toJist(message(properties: props))

        XCTAssertEqual(jist.properties["int"] as? Int, 42)
        XCTAssertEqual(jist.properties["double"] as? Double, 3.14)
        XCTAssertNil(jist.properties["int"] as? String)
    }

    func test_toJist_expectDatePreserved() {
        let date = Date(timeIntervalSince1970: 5555)
        let jist = InboxMessageJistAdapter.toJist(message(properties: ["scheduledAt": date]))

        XCTAssertEqual(jist.properties["scheduledAt"] as? Date, date)
    }

    func test_toJist_array_expectAllMessagesMapped() {
        let messages = [message(properties: ["a": 1]), message(properties: ["b": 2])]
        let jist = InboxMessageJistAdapter.toJist(messages)

        XCTAssertEqual(jist.count, 2)
        XCTAssertEqual(jist[0].properties["a"] as? Int, 1)
        XCTAssertEqual(jist[1].properties["b"] as? Int, 2)
    }
}

class InboxTemplatesRegistryTest: XCTestCase {
    func test_from_whenValidJsonObject_expectRawPreserved() {
        let json = """
        { "welcome": [ { "version": 1 }, { "version": 2 } ], "promo": [ { "version": 1 } ] }
        """
        let registry = InboxTemplatesRegistry.from(jsonData: Data(json.utf8))

        XCTAssertNotNil(registry)
        XCTAssertEqual(Set(registry!.templateNames), ["welcome", "promo"])
        XCTAssertEqual(registry?.versions(forTemplate: "welcome")?.count, 2)
    }

    func test_from_whenNotObject_expectNil() {
        let registry = InboxTemplatesRegistry.from(jsonData: Data("[1,2,3]".utf8))
        XCTAssertNil(registry)
    }
}

// `InboxBrandingTest` lives in its own file (`InboxBrandingTest.swift`), covering theme/patterns,
// the floating-bell icon, the full inbox chrome, and the optional/absent dark-mode pattern.
