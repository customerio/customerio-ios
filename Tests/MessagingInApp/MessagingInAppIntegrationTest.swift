@testable import CioInternalCommon
@testable import CioMessagingInApp
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class MessagingInAppIntegrationTests: IntegrationTest {
    // Bug reported when: using in-app messaging, debug logging enabled, and using iOS version 1.2.8.
    // Report: https://github.com/customerio/customerio-ios/issues/242
    func test_initialize_enableDebugLogs_assertNotCrash() {
        tearDown() // re-initialize with different configuration options.

        CustomerIO.initialize(siteId: testSiteId, apiKey: .random, region: .EU) {
            $0.logLevel = .debug
        }

        MessagingInApp.initialize() // would crash because DiGraph not initialized
    }
}
