import Foundation
import SharedTests
import XCTest

@testable import CioInternalCommon
@testable import CioMessagingInApp

class MessagingInAppTest: UnitTest {
    private let implementationMock = MessagingInAppInstanceMock()

    override func setUp() {
        super.setUp()

        mockCollection.add(mock: implementationMock)
    }

    override func initializeSDKComponents() -> MessagingInAppInstance? {
        // Don't initialize the SDK components because we may want to test the initialize function differently in each test.
        nil
    }

    // MARK: initialize functions with Module initialized

    func test_initialize_givenModuleInitialized_expectModuleIsInitialized() {
        MessagingInApp.setUpSharedInstanceForUnitTest(implementation: implementationMock)

        assertModuleInitialized(isInitialized: true, givenEventListener: nil)
    }

    func test_setEventListener_givenModuleInitialized_expectListenerIsSet() {
        let givenListener = InAppEventListenerMock()

        MessagingInApp.setUpSharedInstanceForUnitTest(implementation: implementationMock)
        MessagingInApp.shared.setEventListener(givenListener)

        assertModuleInitialized(isInitialized: true, givenEventListener: givenListener)
    }

    func test_clearEventListener_givenModuleInitialized_expectListenerIsCleared() {
        let givenListener = InAppEventListenerMock()

        MessagingInApp.setUpSharedInstanceForUnitTest(implementation: implementationMock)
        MessagingInApp.shared.setEventListener(givenListener)
        // clear event listener
        MessagingInApp.shared.setEventListener(nil)

        assertModuleInitialized(
            isInitialized: true, givenEventListener: nil, setEventListenerCallsCount: 2
        )
    }

    // MARK: initialize functions with Module not initialized

    func test_setEventListener_givenModuleNotInitialized_expectListenerNotSet() {
        let givenListener = InAppEventListenerMock()

        MessagingInApp.shared.setEventListener(givenListener)

        assertModuleInitialized(isInitialized: false, givenEventListener: nil)
    }

    func test_inbox_givenModuleNotInitialized_expectNoOpInbox() async {
        // Simple test listener
        class TestListener: InboxMessageChangeListener {
            func onMessagesChanged(messages: [InboxMessage]) {}
        }

        // When module is not initialized, inbox should return a no-op implementation
        let inbox = MessagingInApp.shared.inbox

        // Should not crash and return empty results
        let messages = await inbox.getMessages()
        XCTAssertTrue(messages.isEmpty)

        // These should all safely do nothing without crashing
        let listener = TestListener()
        inbox.addChangeListener(listener)
        inbox.removeChangeListener(listener)

        let testMessage = InboxMessage(
            queueId: "test",
            deliveryId: nil,
            expiry: nil,
            sentAt: Date(),
            topics: [],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )
        inbox.markMessageOpened(message: testMessage)
        inbox.markMessageUnopened(message: testMessage)
        inbox.markMessageDeleted(message: testMessage)
        inbox.trackMessageClicked(message: testMessage, actionName: nil)

        // Verify module is still not initialized
        XCTAssertNil(MessagingInApp.shared.implementation)
    }
}

extension MessagingInAppTest {
    private func assertModuleInitialized(
        isInitialized: Bool, givenEventListener: InAppEventListener?,
        setEventListenerCallsCount: Int? = nil, file: StaticString = #file, line: UInt = #line
    ) {
        if isInitialized {
            XCTAssertNotNil(MessagingInApp.shared.implementation, file: file, line: line)

            let eventListenerCallsCount =
                setEventListenerCallsCount ?? (givenEventListener != nil ? 1 : 0)
            XCTAssertEqual(
                implementationMock.setEventListenerCallsCount, eventListenerCallsCount, file: file,
                line: line
            )
        } else {
            XCTAssertNil(MessagingInApp.shared.implementation, file: file, line: line)
            XCTAssertFalse(implementationMock.mockCalled, file: file, line: line)
        }
    }
}
