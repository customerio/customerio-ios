@testable import CioMessagingInApp
import Common
import Foundation
import SharedTests
import XCTest

class MessagingInAppTest: IntegrationTest {
    private let hooksMock = HooksManagerMock()

    override func setUp() {
        super.setUp()

        MessagingInApp.resetSharedInstance()

        diGraph.override(value: hooksMock, forType: HooksManager.self)
    }

    func test_initializeWithOrganizationId_expectCallModuleInitializeCode() {
        MessagingInApp.initialize(organizationId: String.random)

        XCTAssertTrue(hooksMock.addCalled)
        XCTAssertEqual(hooksMock.addReceivedArguments?.key, .messagingInApp)
    }
}
