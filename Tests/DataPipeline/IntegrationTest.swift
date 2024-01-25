@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
@testable import Segment
import SharedTests

class IntegrationTest: SharedTests.IntegrationTest {
    override func setUp() {
        super.setUp()
        // wait for analytics queue to start emitting events
        CustomerIO.shared.waitUntilStarted()
    }

    override func tearDown() {
        CustomerIO.shared.clearIdentify()
        super.tearDown()
    }
}
