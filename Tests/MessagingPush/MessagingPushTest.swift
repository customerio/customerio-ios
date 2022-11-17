@testable import CioMessagingPush
import Common
import Foundation
import SharedTests
import XCTest

class MessagingPushTest: IntegrationTest {
    private let hooksMock = HooksManagerMock()

    override func setUp() {
        super.setUp()

        diGraph.override(value: hooksMock, forType: HooksManager.self)
    }

    func test_initialize_expectCallModuleInitializeCode() {
        MessagingPush.initialize()

        XCTAssertTrue(hooksMock.addCalled)
        XCTAssertEqual(hooksMock.addReceivedArguments?.key, .messagingPush)
    }
}
