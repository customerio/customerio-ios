@testable import CioInternalCommon
@_spi(VisualInbox) @testable import CioMessagingInApp
@testable import CioMessagingInAppMocks
import Foundation
import SharedTests
import XCTest

/// Coverage for `VisualInboxProviderImpl.currentSnapshot()` — specifically Fix D.
///
/// Fix D: the snapshot used to read the message list and the unread count via TWO separate
/// `jistMessages()` reads, so a store change landing between them could yield a badge that
/// disagrees with the list it is shown next to. The fix reads the list ONCE and derives the count
/// from that same array. These tests assert the badge always matches the emitted message list.
final class VisualInboxProviderTest: XCTestCase {
    private var networkStub: InboxNetworkClientStub!
    private var inAppMessageManagerMock: InAppMessageManagerMock!
    private var keyValueStore: InMemorySharedKeyValueStorage!
    private var sleeperMock: SleeperMock!
    private var dateUtilStub: DateUtilStub!
    private var logger: Logger!

    private let templatesJSON = #"{ "welcome": [ { "version": 1 } ] }"#
    private let brandingJSON = #"{ "theme": { "radius": 8 }, "patterns": { "inbox": { "background": "white" } } }"#

    override func setUp() {
        super.setUp()
        networkStub = InboxNetworkClientStub()
        inAppMessageManagerMock = InAppMessageManagerMock()
        inAppMessageManagerMock.subscribeReturnValue = Task {}
        keyValueStore = InMemorySharedKeyValueStorage()
        sleeperMock = SleeperMock()
        sleeperMock.sleepClosure = { _ in }
        dateUtilStub = DateUtilStub()
        dateUtilStub.givenNow = Date(timeIntervalSince1970: 0)
        logger = DIGraphShared.shared.logger
    }

    private func makeRepository() -> VisualInboxRepositoryImpl {
        VisualInboxRepositoryImpl(
            networkClient: networkStub,
            inAppMessageManager: inAppMessageManagerMock,
            keyValueStore: keyValueStore,
            sleeper: sleeperMock,
            dateUtil: dateUtilStub,
            logger: logger
        )
    }

    private func message(queueId: String, opened: Bool) -> InboxMessage {
        InboxMessage(queueId: queueId, deliveryId: nil, expiry: nil, sentAt: Date(timeIntervalSince1970: 100), topics: ["cio_inbox"], type: "card", opened: opened, priority: nil, properties: [:])
    }

    /// First `observe()` emission must carry a badge that matches its own message list (one read).
    func test_observe_firstSnapshot_badgeMatchesMessageList() async {
        let messages = [
            message(queueId: "a", opened: false),
            message(queueId: "b", opened: true),
            message(queueId: "c", opened: false)
        ]
        inAppMessageManagerMock.underlyingState = InAppMessageState().copy(userId: "user-1", inboxMessages: messages)

        let repo = makeRepository()
        await repo.setInboxEnabled(true)
        networkStub.handler = { [templatesJSON, brandingJSON] endpoint, _ in
            endpoint == .getTemplates
                ? InboxNetworkClientStub.response(json: templatesJSON)
                : InboxNetworkClientStub.response(json: brandingJSON)
        }
        await repo.enableAndLoad()

        let provider = VisualInboxProviderImpl(
            repository: repo,
            inbox: NoOpNotificationInboxFake(),
            inAppMessageManager: inAppMessageManagerMock
        )

        let snapshot = await firstSnapshot(from: provider)

        // The badge is derived from the SAME message array, so the two always agree.
        let unopenedInList = snapshot.messages.filter { !$0.opened }.count
        XCTAssertEqual(snapshot.unopenedCount, unopenedInList)
        XCTAssertEqual(snapshot.unopenedCount, 2)
        XCTAssertEqual(snapshot.messages.count, 3)
    }

    /// Reads only the first emission from the provider's `observe()` stream.
    private func firstSnapshot(from provider: VisualInboxProviderImpl) async -> VisualInboxSnapshot {
        for await snapshot in provider.observe() {
            return snapshot
        }
        XCTFail("observe() produced no snapshot")
        return VisualInboxSnapshot(state: .idle, messages: [], unopenedCount: 0, templatesJSON: nil, themeJSON: nil)
    }
}

/// Minimal no-op `NotificationInbox` used so the provider can be constructed. The provider's
/// snapshot path never touches the inbox (it reads messages from the repository); the inbox is only
/// used by `markOpened`, which these tests don't exercise.
private final class NoOpNotificationInboxFake: NotificationInbox, @unchecked Sendable {
    func getMessages(topic: String?) async -> [InboxMessage] {
        []
    }

    @MainActor func addChangeListener(_ listener: NotificationInboxChangeListener, topic: String?) {}
    func removeChangeListener(_ listener: NotificationInboxChangeListener) {}
    func markMessageOpened(message: InboxMessage) {}
    func markMessageUnopened(message: InboxMessage) {}
    func markMessageDeleted(message: InboxMessage) {}
    func trackMessageClicked(message: InboxMessage, actionName: String?) {}
    func setInboxEventListener(_ listener: InboxEventListener?) {}
    func notifyMessageActionTaken(message: InboxMessage, actionValue: String, actionName: String) -> Bool {
        false
    }

    func messages(topic: String?) -> AsyncStream<[InboxMessage]> {
        AsyncStream { $0.finish() }
    }
}
