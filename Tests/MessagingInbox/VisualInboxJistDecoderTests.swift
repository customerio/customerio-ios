@testable import CioMessagingInbox
import Foundation
import Jist
import XCTest

/// Coverage for the raw-JSON → Jist-types bridge that feeds `JistView` (item 7).
final class VisualInboxJistDecoderTests: XCTestCase {
    // MARK: - templates

    func test_decodeTemplates_whenValidRegistry_thenDecodesVersionedTemplates() {
        let raw: [String: Any] = [
            "$schema": "https://example/schema.json", // non-array entry — must be skipped
            "basic": [
                ["version": "1", "root": ["type": "text", "name": "body"]]
            ]
        ]

        let templates = VisualInboxJistDecoder.decodeTemplates(raw)

        XCTAssertNil(templates["$schema"])
        XCTAssertEqual(templates["basic"]?.count, 1)
        XCTAssertEqual(templates["basic"]?.first?.version, "1")
    }

    func test_decodeTemplates_whenNil_thenEmpty() {
        XCTAssertTrue(VisualInboxJistDecoder.decodeTemplates(nil).isEmpty)
    }

    // MARK: - data (message properties)

    func test_decodeData_whenNestedProperties_thenPreservesStructure() {
        let properties: [String: Any] = [
            "title": "Hello",
            "count": 3,
            "flag": true,
            "nested": ["k": "v"]
        ]

        let data = VisualInboxJistDecoder.decodeData(properties)

        XCTAssertEqual(data["title"], .string("Hello"))
        XCTAssertEqual(data["count"], .number(3))
        XCTAssertEqual(data["flag"], .bool(true))
        XCTAssertEqual(data["nested"], .object(["k": .string("v")]))
    }

    // MARK: - theme

    func test_decodeTheme_whenValid_thenDecodes() {
        let raw: [String: Any] = ["heading": ["color": "#000000"]]

        let theme = VisualInboxJistDecoder.decodeTheme(raw)

        XCTAssertEqual(theme["heading"], .object(["color": .string("#000000")]))
    }

    func test_decodeTheme_whenNil_thenEmpty() {
        XCTAssertTrue(VisualInboxJistDecoder.decodeTheme(nil).isEmpty)
    }
}
