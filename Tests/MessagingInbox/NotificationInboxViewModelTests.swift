import CioInternalCommon
import CioMessagingInApp
@testable import CioMessagingInbox
import Combine
import Foundation
import XCTest

/// Lightweight hand-written fake of the headless `NotificationInbox` API.
///
/// Avoids the auto-generated mock pipeline so this test target needs no sourcery config.
/// Drives the `messages()` stream via a stored continuation so tests can push updates.
private final class FakeNotificationInbox: NotificationInbox, @unchecked Sendable {
    private let initialMessages: [InboxMessage]
    private var continuation: AsyncStream<[InboxMessage]>.Continuation?

    private(set) var markOpenedCalls: [String] = []
    private(set) var markUnopenedCalls: [String] = []

    init(initialMessages: [InboxMessage]) {
        self.initialMessages = initialMessages
    }

    func emit(_ messages: [InboxMessage]) {
        continuation?.yield(messages)
    }

    func getMessages(topic: String?) async -> [InboxMessage] {
        initialMessages
    }

    func messages(topic: String?) -> AsyncStream<[InboxMessage]> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
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

@available(iOS 13.0, *)
@MainActor
final class NotificationInboxViewModelTests: XCTestCase {
    func test_unreadCount_whenMixedMessages_thenCountsOnlyUnopened() {
        let messages = [
            makeMessage(queueId: "a", opened: false),
            makeMessage(queueId: "b", opened: true),
            makeMessage(queueId: "c", opened: false)
        ]
        let viewModel = NotificationInboxViewModel(inbox: FakeNotificationInbox(initialMessages: messages))

        let exp = expectation(description: "initial messages loaded")
        let cancellable = viewModel.$messages.sink { loaded in
            if loaded.count == messages.count { exp.fulfill() }
        }
        viewModel.start()
        wait(for: [exp], timeout: 2.0)
        cancellable.cancel()

        XCTAssertEqual(viewModel.unreadCount, 2)
    }

    func test_togglePanel_whenCalled_thenFlipsState() {
        let viewModel = NotificationInboxViewModel(inbox: FakeNotificationInbox(initialMessages: []))

        XCTAssertFalse(viewModel.isPanelOpen)
        viewModel.togglePanel()
        XCTAssertTrue(viewModel.isPanelOpen)
        viewModel.togglePanel()
        XCTAssertFalse(viewModel.isPanelOpen)
    }

    func test_toggleOpened_whenUnopened_thenMarksOpened() {
        let fake = FakeNotificationInbox(initialMessages: [])
        let viewModel = NotificationInboxViewModel(inbox: fake)

        viewModel.toggleOpened(makeMessage(queueId: "x", opened: false))
        XCTAssertEqual(fake.markOpenedCalls, ["x"])
        XCTAssertTrue(fake.markUnopenedCalls.isEmpty)
    }

    func test_toggleOpened_whenOpened_thenMarksUnopened() {
        let fake = FakeNotificationInbox(initialMessages: [])
        let viewModel = NotificationInboxViewModel(inbox: fake)

        viewModel.toggleOpened(makeMessage(queueId: "y", opened: true))
        XCTAssertEqual(fake.markUnopenedCalls, ["y"])
        XCTAssertTrue(fake.markOpenedCalls.isEmpty)
    }
}
