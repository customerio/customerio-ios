@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

class MessageQueueManagerTest: UnitTest {
    private var manager: MessageQueueManagerImpl!

    private let gistMock = GistInstanceMock()
    private let eventBusMock = EventBusHandlerMock()

    override func setUp() {
        super.setUp()

        DIGraphShared.shared.override(value: gistMock, forType: GistInstance.self)
        DIGraphShared.shared.override(value: eventBusMock, forType: EventBusHandler.self)

        manager = MessageQueueManagerImpl()
    }

    // MARK: getInlineMessages

    func test_getInlineMessages_givenEmptyQueue_expectEmptyArray() {
        let actualMessages = manager.getInlineMessages(forElementId: .random)

        XCTAssertTrue(actualMessages.isEmpty)
    }

    func test_getInlineMessages_givenQueueNotEmpty_expectGetInlineMessagesWithElementId() {
        let givenElementId = String.random
        let givenModalMessage = Message.random
        let givenInlineMessageDifferentElementId = Message.randomInline
        let givenInlineMessageSameElementId = Message(messageId: .random, campaignId: .random, elementId: givenElementId)

        manager.localMessageStore = [
            "1": givenModalMessage,
            "2": givenInlineMessageDifferentElementId,
            "3": givenInlineMessageSameElementId
        ]

        let actualMessages = manager.getInlineMessages(forElementId: givenElementId)

        XCTAssertEqual(actualMessages.count, 1)
        XCTAssertEqual(actualMessages[0].elementId, givenElementId)
        XCTAssertTrue(actualMessages[0].isInlineMessage)
    }

    func test_getInlineMessages_expectSortByPriority() {
        let givenElementId = String.random

        let givenMessage1 = Message(elementId: givenElementId, priority: 1)
        let givenMessage2 = Message(elementId: givenElementId, priority: 0)
        let givenMessage3 = Message(elementId: givenElementId, priority: nil)

        manager.localMessageStore = [
            "1": givenMessage1,
            "2": givenMessage2,
            "3": givenMessage3
        ]

        let actualMessages = manager.getInlineMessages(forElementId: givenElementId)

        XCTAssertEqual(actualMessages, [givenMessage2, givenMessage1, givenMessage3])
    }

    func test_getInlineMessages_givenQueueMessageHasPageRule_pageRuleMatch_expectInlineMessage() {
        let givenElementId = String.random
        let currentRoute = "^(Dashboard)$"

        let givenMessage1 = Message(pageRule: currentRoute, elementId: givenElementId, priority: 0)
        let givenMessage2 = Message(pageRule: currentRoute, elementId: givenElementId, priority: 1)
        let givenMessage3 = Message(elementId: givenElementId, priority: nil)

        manager.localMessageStore = [
            "1": givenMessage1,
            "2": givenMessage2,
            "3": givenMessage3
        ]
        Gist.shared.setCurrentRoute("Dashboard")
        let actualMessages = manager.getInlineMessages(forElementId: givenElementId)
        XCTAssertEqual(actualMessages, [givenMessage1, givenMessage2, givenMessage3])
    }

    func test_getInlineMessages_givenQueueMessageHasPageRule_givenNoSetCurrentRoute_expectEmptyArray() {
        let givenElementId1 = String.random
        let givenElementId2 = String.random
        let givenElementId3 = String.random
        let currentRoute = String.random

        let givenMessage1 = Message(pageRule: currentRoute, elementId: givenElementId1, priority: 1)
        let givenMessage2 = Message(pageRule: currentRoute, elementId: givenElementId2, priority: 0)
        let givenMessage3 = Message(elementId: givenElementId3, priority: 0)

        manager.localMessageStore = [
            "1": givenMessage1,
            "2": givenMessage2,
            "3": givenMessage3
        ]
        let actualMessages = manager.getInlineMessages(forElementId: givenElementId1)
        XCTAssertEqual(actualMessages, [])
    }

    // MARK: - processFetchedMessages

    func test_processFetchedMessages_givenEmptyMessages_expectNoProcessingDone() {
        manager.processFetchedMessages([])

        XCTAssertTrue(modalMessageProcessed.isEmpty)
        XCTAssertTrue(inlineMessagesProcessed.isEmpty)
    }

    func test_processFetchedMessages_givenInlineMessages_expectStoreInLocalQueue() {
        let givenInlineMessage = Message.randomInline

        manager.processFetchedMessages([givenInlineMessage])

        XCTAssertEqual(inlineMessagesProcessed.count, 1)
        XCTAssertTrue(modalMessageProcessed.isEmpty)
    }

    func test_processFetchedMessages_givenModalMessages_expectForwardRequestToShowMessage() {
        let givenModalMessage = Message.random
        gistMock.showMessageReturnValue = true

        manager.processFetchedMessages([givenModalMessage])

        XCTAssertEqual(modalMessageProcessed.count, 1)
        XCTAssertTrue(inlineMessagesProcessed.isEmpty)
    }

    func test_processFetchedMessages_expectSendEventBusEventAfterProcessing() {
        XCTAssertEqual(eventBusMock.postEventCallsCount, 0)

        manager.processFetchedMessages([Message.randomInline])

        XCTAssertEqual(eventBusMock.postEventCallsCount, 1)
        XCTAssertTrue(eventBusMock.postEventArguments is InAppMessagesFetchedEvent)
    }
}

extension MessageQueueManagerTest {
    var modalMessageProcessed: [Message] {
        gistMock.showMessageReceivedInvocations.map(\.message)
    }

    var inlineMessagesProcessed: [Message] {
        manager.localMessageStore.values.filter(\.isInlineMessage)
    }
}
