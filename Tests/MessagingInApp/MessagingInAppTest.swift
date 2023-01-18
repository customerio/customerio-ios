@testable import CioMessagingInApp
@testable import CioTracking
@testable import Common
import Foundation
@testable import Gist
import SharedTests
import XCTest

class MessagingInAppTest: UnitTest {
    private let hooksMock = HooksManagerMock()
    private let implementationMock = MessagingInAppInstanceMock()
    private let sdkInitializedUtilMock = SdkInitializedUtilMock()

    override func setUp() {
        super.setUp()

        MessagingInApp.resetSharedInstance()

        sdkInitializedUtilMock.postInitializedData = (siteId: testSiteId, diGraph: diGraph)

        diGraph.override(value: hooksMock, forType: HooksManager.self)
    }

    func test_initialize_noEventListener_expectCallModuleInitializeCode() {
        MessagingInApp.initialize(organizationId: String.random, eventListener: nil, implementation: implementationMock, sdkInitializedUtil: sdkInitializedUtilMock)

        XCTAssertEqual(hooksMock.addCallsCount, 1)
        XCTAssertEqual(hooksMock.addReceivedArguments?.key, .messagingInApp)
    }

    func test_initialize_givenEventListener_expectCallModuleInitializeCode() {
        MessagingInApp.initialize(organizationId: String.random, eventListener: InAppEventListenerMock(), implementation: implementationMock, sdkInitializedUtil: sdkInitializedUtilMock)

        XCTAssertEqual(hooksMock.addCallsCount, 1)
        XCTAssertEqual(hooksMock.addReceivedArguments?.key, .messagingInApp)
    }
}
