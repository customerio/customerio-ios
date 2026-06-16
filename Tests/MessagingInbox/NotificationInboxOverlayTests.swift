import CioInternalCommon
import CioMessagingInApp
@testable import CioMessagingInbox
import Foundation
import XCTest

/// Minimal coverage for the `MessagingInbox` module.
///
/// `NotificationInboxOverlay` now holds its state inline as SwiftUI `@State` (no view model), so
/// there is no separate state-holder to unit test. These tests instead lock the headless
/// read/unread contract that the overlay's row action (`toggleOpened`) relies on: an unopened
/// message gets marked opened, and vice versa.
@available(iOS 13.0, *)
final class NotificationInboxReadStateTests: XCTestCase {
    func test_markOpened_whenMessageUnopened_thenInboxRecordsOpen() {
        let inbox = FakeNotificationInbox()
        let message = makeMessage(queueId: "a", opened: false)

        // Mirrors the overlay's row action for an unopened message.
        inbox.markMessageOpened(message: message)

        XCTAssertEqual(inbox.markOpenedCalls, ["a"])
        XCTAssertTrue(inbox.markUnopenedCalls.isEmpty)
    }

    func test_markUnopened_whenMessageOpened_thenInboxRecordsUnopen() {
        let inbox = FakeNotificationInbox()
        let message = makeMessage(queueId: "b", opened: true)

        // Mirrors the overlay's row action for an already-opened message.
        inbox.markMessageUnopened(message: message)

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
