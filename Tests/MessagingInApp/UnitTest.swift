@testable import CioMessagingInApp
import Foundation
import SharedTests

internal class UnitTest: SharedTests.UnitTest {
    public var moduleDiGraph: DIMessagingInApp {
        DIMessagingInApp.getInstance(siteId: testSiteId)
    }

    override func tearDown() {
        MessagingInAppMocks.shared.resetAll()

        moduleDiGraph.resetOverrides()

        super.tearDown()
    }
}
