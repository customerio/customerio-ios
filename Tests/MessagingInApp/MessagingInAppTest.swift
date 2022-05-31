@testable import CioMessagingInApp
@testable import CioTracking
import Foundation
import Gist
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
}
