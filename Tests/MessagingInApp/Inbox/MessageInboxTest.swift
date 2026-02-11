@testable import CioInternalCommon
@testable import CioMessagingInApp
import XCTest

class MessageInboxTest: UnitTest {
    private var messageInbox: MessageInbox!
    private var inAppMessageManagerMock: InAppMessageManagerMock!

    override func setUp() {
        super.setUp()

        inAppMessageManagerMock = InAppMessageManagerMock()
        mockCollection.add(mocks: [inAppMessageManagerMock])

        messageInbox = MessageInbox(
            logger: diGraphShared.logger,
            inAppMessageManager: inAppMessageManagerMock
        )
    }

    override func tearDown() {
        messageInbox = nil
        inAppMessageManagerMock = nil
        super.tearDown()
    }

    func test_inboxAccessibleViaModule_expectNotNil() {
        MessagingInApp.setUpSharedInstanceForIntegrationTest(
            diGraphShared: diGraphShared,
            config: messagingInAppConfigOptions
        )

        let inbox = MessagingInApp.shared.inbox
        XCTAssertNotNil(inbox)
    }
}
