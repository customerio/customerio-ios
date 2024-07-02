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

    // We expect that given an identical set of Messages as input, no matter the order, the output order is always the same.
    func test_getInlineMessages_givenMessagesWithSamePriority_expectConsistentReturnValue() {
        let givenElementId = String.random

        // Create multiple messages with the same priority. This means we need to use a different Message property to sort the Messages.
        let givenMessage1 = Message(queueId: .random, elementId: givenElementId, priority: 1)
        let givenMessage2 = Message(queueId: .random, elementId: givenElementId, priority: 1)
        let givenMessage3 = Message(queueId: .random, elementId: givenElementId, priority: 1)

        // Because queueId is optional, add some messages with a nil queueid to test the sorted order is still consistent.
        let givenMessage4 = Message(queueId: nil, elementId: givenElementId, priority: 1)
        let givenMessage5 = Message(queueId: nil, elementId: givenElementId, priority: 1)

        // Get the output 1 time to get a sample to compare against.
        manager.localMessageStore = [
            "1": givenMessage1,
            "2": givenMessage2,
            "3": givenMessage3,
            "4": givenMessage4,
            "5": givenMessage5
        ]
        let expectedOrder = manager.getInlineMessages(forElementId: givenElementId)

        // Shuffle the input Messages Array and assert that the output is always the same.
        for _ in 0 ..< 100 {
            let shuffled = manager.localMessageStore.shuffled()

            // Shuffle the order of the message store dictionary.
            manager.localMessageStore = [:]
            for message in shuffled {
                manager.localMessageStore[.random] = message.value
            }

            // We expect that the output order is always the same
            XCTAssertEqual(expectedOrder, manager.getInlineMessages(forElementId: givenElementId))
        }
    }

    // we expect the messages returned are in the same order before and after a fetch is performed.
    func test_getInlineMessages_expectConsistentReturnValueAfterFetch() {
        let givenElementId = String.random

        // Create multiple messages with the same priority. This means we need to use a different Message property to sort the Messages.
        let givenMessageBeforeFetch1 = Message(queueId: .random, elementId: givenElementId, priority: 1)
        let givenMessageBeforeFetch2 = Message(queueId: .random, elementId: givenElementId, priority: 1)
        let givenMessageBeforeFetch3 = Message(queueId: .random, elementId: givenElementId, priority: 1)

        // Get the output 1 time to get a sample to compare against.
        manager.localMessageStore = [
            "1": givenMessageBeforeFetch1,
            "2": givenMessageBeforeFetch2,
            "3": givenMessageBeforeFetch3
        ]
        let actualOrderBeforeFetch = manager.getInlineMessages(forElementId: givenElementId)

        // Create new Message instances and assert that the output is always the same.
        for _ in 0 ..< 100 {
            let givenMessageAfterFetch1 = Message(queueId: givenMessageBeforeFetch1.id, elementId: givenElementId, priority: givenMessageBeforeFetch1.priority)
            let givenMessageAfterFetch2 = Message(queueId: givenMessageBeforeFetch2.id, elementId: givenElementId, priority: givenMessageBeforeFetch2.priority)
            let givenMessageAfterFetch3 = Message(queueId: givenMessageBeforeFetch3.id, elementId: givenElementId, priority: givenMessageBeforeFetch3.priority)

            manager.localMessageStore = [
                "1": givenMessageAfterFetch1,
                "2": givenMessageAfterFetch2,
                "3": givenMessageAfterFetch3
            ]

            // We expect that the output order is always the same
            XCTAssertEqual(actualOrderBeforeFetch, manager.getInlineMessages(forElementId: givenElementId))
        }
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
