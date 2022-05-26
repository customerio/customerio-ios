@testable import CioMessagingInApp
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class MessagingInAppTest: UnitTest {
    private var messagingInApp: MessagingInApp!

    private let inAppProviderMock = InAppProviderMock()

    override func setUp() {
        super.setUp()

        moduleDiGraph.override(.inAppProvider, value: inAppProviderMock, forType: InAppProvider.self)

        messagingInApp = MessagingInApp(diGraph: diGraph, moduleDiGraph: moduleDiGraph, siteId: testSiteId)
    }

    // MARK: initialize

    func test_initialize_givenOrganizationId_expectInitializeGistSDK() {
        let givenId = String.random

        messagingInApp.initialize(organizationId: givenId)

        XCTAssertTrue(inAppProviderMock.initializeCalled)
    }
}
