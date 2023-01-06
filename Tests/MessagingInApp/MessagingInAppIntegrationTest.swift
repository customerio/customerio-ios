@testable import CioTracking
@testable import CioMessagingInApp
@testable import Common
import Foundation
import SharedTests
import XCTest

class MessagingInAppIntegrationTests: IntegrationTest {
    
    // Reproduce bug: https://github.com/customerio/customerio-ios/issues/242
    func test_initialize_enableDebugLogs_() {
        CustomerIO.resetSharedInstance()
        
        CustomerIO.initialize(siteId: testSiteId, apiKey: .random)
        CustomerIO.config {
            $0.logLevel = .debug
        }
        
        MessagingInApp.shared.initialize(organizationId: .random)
    }
}
