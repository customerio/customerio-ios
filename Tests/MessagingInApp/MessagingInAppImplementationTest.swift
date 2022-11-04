@testable import CioMessagingInApp
@testable import CioTracking
import Foundation
import Gist
import SharedTests
import XCTest

class MessagingInAppImplementationTest: UnitTest {
    private var messagingInApp: MessagingInAppImplementation!

    private let inAppProviderMock = InAppProviderMock()

    override func setUp() {
        super.setUp()

        diGraph.override(value: inAppProviderMock, forType: InAppProvider.self)

        messagingInApp = MessagingInAppImplementation(siteId: testSiteId, diGraph: diGraph)
    }

    // MARK: initialize

    func test_initialize_givenOrganizationId_expectInitializeGistSDK() {
        let givenId = String.random

        messagingInApp.initialize(organizationId: givenId)

        XCTAssertTrue(inAppProviderMock.initializeCalled)
    }

    // MARK: profile hooks

    func test_givenProfileIdentified_expectSetupWithInApp() {
        let given = String.random

        messagingInApp.profileIdentified(identifier: given)

        XCTAssertEqual(inAppProviderMock.setProfileIdentifierCallsCount, 1)
        XCTAssertEqual(inAppProviderMock.setProfileIdentifierReceivedArguments, given)
    }

    func test_givenProfileNoLongerIdentified_expectRemoveFromInApp() {
        messagingInApp.beforeProfileStoppedBeingIdentified(oldIdentifier: String.random)

        XCTAssertEqual(inAppProviderMock.clearIdentifyCallsCount, 1)
    }

    // MARK: screen view hooks

    func test_givenScreenViewed_expectSetRouteOnInApp() {
        let given = String.random

        messagingInApp.screenViewed(name: given)

        XCTAssertEqual(inAppProviderMock.setRouteCallsCount, 1)
        XCTAssertEqual(inAppProviderMock.setRouteReceivedArguments, given)
    }
}
