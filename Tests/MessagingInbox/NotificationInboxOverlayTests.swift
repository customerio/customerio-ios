import CioInternalCommon
import CioMessagingInApp
@testable import CioMessagingInbox
import Foundation
import XCTest

/// Coverage for the `MessagingInbox` module.
///
/// `NotificationInboxOverlay` holds its state inline as SwiftUI `@State` (no view model), so there
/// is no separate state-holder to unit test. SwiftUI lifecycle (`onAppear`, the live stream) is not
/// unit-testable here and is intentionally not exercised. These tests instead cover the overlay's
/// testable seams: the pure `unreadCount(in:)` helper that drives the badge, and the `toggleOpened`
/// row action wired to the injected inbox.
@available(iOS 13.0, *)
final class NotificationInboxOverlayTests: XCTestCase {
    // MARK: - unreadCount(in:)

    func test_unreadCount_whenMixedOpenedAndUnopened_thenCountsOnlyUnopened() {
        let messages = [
            makeMessage(queueId: "a", opened: false),
            makeMessage(queueId: "b", opened: true),
            makeMessage(queueId: "c", opened: false),
            makeMessage(queueId: "d", opened: true)
        ]

        XCTAssertEqual(NotificationInboxOverlay.unreadCount(in: messages), 2)
    }

    func test_unreadCount_whenEmpty_thenZero() {
        XCTAssertEqual(NotificationInboxOverlay.unreadCount(in: []), 0)
    }

    // MARK: - toggleOpened(_:)

    func test_toggleOpened_whenMessageUnopened_thenInboxRecordsOpen() {
        let inbox = FakeNotificationInbox()
        let overlay = NotificationInboxOverlay(inbox: inbox)

        overlay.toggleOpened(makeMessage(queueId: "a", opened: false))

        XCTAssertEqual(inbox.markOpenedCalls, ["a"])
        XCTAssertTrue(inbox.markUnopenedCalls.isEmpty)
    }

    func test_toggleOpened_whenMessageOpened_thenInboxRecordsUnopen() {
        let inbox = FakeNotificationInbox()
        let overlay = NotificationInboxOverlay(inbox: inbox)

        overlay.toggleOpened(makeMessage(queueId: "b", opened: true))

        XCTAssertEqual(inbox.markUnopenedCalls, ["b"])
        XCTAssertTrue(inbox.markOpenedCalls.isEmpty)
    }
}

/// Lightweight hand-written fake of the headless `NotificationInbox` API.
///
/// Avoids the auto-generated mock pipeline so this test target needs no sourcery config.
private final class FakeNotificationInbox: NotificationInbox, @unchecked Sendable {
    private(set) var markOpenedCalls: [String] = []
    private(set) var markUnopenedCalls: [String] = []

    func getMessages(topic: String?) async -> [InboxMessage] {
        []
    }

    func messages(topic: String?) -> AsyncStream<[InboxMessage]> {
        AsyncStream { _ in }
    }

    @MainActor
    func addChangeListener(_ listener: NotificationInboxChangeListener, topic: String?) {}
    func removeChangeListener(_ listener: NotificationInboxChangeListener) {}

    func markMessageOpened(message: InboxMessage) {
        markOpenedCalls.append(message.queueId)
    }

    func markMessageUnopened(message: InboxMessage) {
        markUnopenedCalls.append(message.queueId)
    }

    func markMessageDeleted(message: InboxMessage) {}
    func trackMessageClicked(message: InboxMessage, actionName: String?) {}
}

private func makeMessage(queueId: String, opened: Bool) -> InboxMessage {
    InboxMessage(
        queueId: queueId,
        deliveryId: nil,
        expiry: nil,
        sentAt: Date(),
        topics: [],
        type: "test",
        opened: opened,
        priority: nil,
        properties: [:]
    )
}
