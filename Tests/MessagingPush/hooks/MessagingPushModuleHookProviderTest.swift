@testable import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class MessagingPushModuleHookProviderTest: IntegrationTest {
    private var hookProvider: MessagingPushModuleHookProvider!

    override func setUp() {
        super.setUp()

        hookProvider = MessagingPushModuleHookProvider(siteId: testSiteId)
    }

    func test_profileIdentifyHook_expectNotNil() {
        XCTAssertNotNil(hookProvider.profileIdentifyHook)
    }

    func test_queueRunnerHook_expectNotNil() {
        XCTAssertNotNil(hookProvider.queueRunnerHook)
    }
}
