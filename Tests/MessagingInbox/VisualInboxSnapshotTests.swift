@_spi(VisualInbox) import CioMessagingInApp
import Foundation
import XCTest

/// Coverage for `VisualInboxSnapshot`'s structural equality, which de-dupes `observe()` emissions.
///
/// Fix C: equality previously ignored each message's `properties` and the raw `templatesJSON` /
/// `themeJSON`, so a content-only change (same ids/state/count but new render payload) compared
/// EQUAL and was dropped by `emitSnapshot` — leaving the overlay rendering stale Jist rows/theme.
/// These tests pin that such render-payload changes now count as DIFFERENT (so they're emitted),
/// while truly-identical snapshots still compare equal (so genuine dupes are still dropped).
@available(iOS 13.0, *)
final class VisualInboxSnapshotTests: XCTestCase {
    private func snapshot(
        state: VisualInboxState = .visible(messageCount: 1),
        messages: [VisualInboxMessageSnapshot],
        unopenedCount: Int = 0,
        templatesJSON: [String: Any]? = nil,
        themeJSON: [String: Any]? = nil
    ) -> VisualInboxSnapshot {
        VisualInboxSnapshot(
            state: state,
            messages: messages,
            unopenedCount: unopenedCount,
            templatesJSON: templatesJSON,
            themeJSON: themeJSON
        )
    }

    private func message(id: String = "a", properties: [String: Any] = [:]) -> VisualInboxMessageSnapshot {
        VisualInboxMessageSnapshot(id: id, type: "card", properties: properties, opened: false, sentAt: Date(timeIntervalSince1970: 0))
    }

    func test_equality_whenFullyIdentical_thenEqual() {
        let a = snapshot(messages: [message(properties: ["title": "Hi"])], templatesJSON: ["card": 1], themeJSON: ["bg": "white"])
        let b = snapshot(messages: [message(properties: ["title": "Hi"])], templatesJSON: ["card": 1], themeJSON: ["bg": "white"])
        XCTAssertEqual(a, b)
    }

    func test_equality_whenOnlyMessagePropertiesDiffer_thenDifferent() {
        // Same id/opened/type/state/count, but the render payload changed — must NOT compare equal.
        let a = snapshot(messages: [message(properties: ["title": "Hi"])])
        let b = snapshot(messages: [message(properties: ["title": "Updated"])])
        XCTAssertNotEqual(a, b)
    }

    func test_equality_whenOnlyNestedMessagePropertiesDiffer_thenDifferent() {
        let a = snapshot(messages: [message(properties: ["cta": ["label": "Open"]])])
        let b = snapshot(messages: [message(properties: ["cta": ["label": "Dismiss"]])])
        XCTAssertNotEqual(a, b)
    }

    func test_equality_whenOnlyTemplatesJSONDiffers_thenDifferent() {
        let a = snapshot(messages: [message()], templatesJSON: ["card": [["body": "v1"]]])
        let b = snapshot(messages: [message()], templatesJSON: ["card": [["body": "v2"]]])
        XCTAssertNotEqual(a, b)
    }

    func test_equality_whenOnlyThemeJSONDiffers_thenDifferent() {
        let a = snapshot(messages: [message()], themeJSON: ["bg": "white"])
        let b = snapshot(messages: [message()], themeJSON: ["bg": "black"])
        XCTAssertNotEqual(a, b)
    }

    func test_equality_whenThemeJSONNilVsPresent_thenDifferent() {
        let a = snapshot(messages: [message()], themeJSON: nil)
        let b = snapshot(messages: [message()], themeJSON: ["bg": "white"])
        XCTAssertNotEqual(a, b)
    }

    func test_equality_whenBothRenderPayloadsNil_thenEqual() {
        // nil == nil for both dictionaries; identical messages/state/count → still a dup.
        let a = snapshot(messages: [message()], templatesJSON: nil, themeJSON: nil)
        let b = snapshot(messages: [message()], templatesJSON: nil, themeJSON: nil)
        XCTAssertEqual(a, b)
    }

    func test_equality_whenOpenedFlagDiffers_thenDifferent() {
        // Existing behavior preserved: opened-state change is still a difference.
        let a = snapshot(messages: [VisualInboxMessageSnapshot(id: "a", type: "card", properties: [:], opened: false, sentAt: Date(timeIntervalSince1970: 0))])
        let b = snapshot(messages: [VisualInboxMessageSnapshot(id: "a", type: "card", properties: [:], opened: true, sentAt: Date(timeIntervalSince1970: 0))])
        XCTAssertNotEqual(a, b)
    }
}
