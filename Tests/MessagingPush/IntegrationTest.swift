@testable import CioMessagingPush
import Foundation
import SharedTests

class IntegrationTest: SharedTests.IntegrationTest {
    override func setUp() {
        MessagingPush.resetSharedInstance()

        super.setUp()

        // CIO is already initialized from super class

        // Sets up features such as hooks for test to be more realistic to production
        MessagingPush.initialize()
    }
}
