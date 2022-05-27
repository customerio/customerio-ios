@testable import CioMessagingInApp
import Foundation
import SharedTests

// Override default `UnitTest` class to provide extra functionality just for this module.
// Keep the class name the same so all test classes in the whole project are simplified using
// the same class name to extend.
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
