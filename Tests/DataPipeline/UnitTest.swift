@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
@testable import Segment
import SharedTests

class UnitTest: SharedTests.UnitTest {
    // When calling CustomerIOInstance functions in the test functions, use this `CustomerIO` instance.
    // This is a workaround until this code base contains implementation tests. There have been bugs
    // that have gone undiscovered in the code when `CustomerIO` passes a request to `DataPipelineImplementation`.
    open var customerIO: CustomerIO!
    open var analytics: Analytics!

    override func setUp() {
        super.setUp()
        // override dependencies before creating SDK instance, as Shared graph may be initialized and used immediately
        overrideDependencies()
        // creates CustomerIO instance and set necessary values for testing
        customerIO = createCustomerIOInstance()
        // if the analytics instance is nil, it indicates that the SDK setup is incorrect
        analytics = customerIO.analytics!
        // wait for analytics queue to start emitting events
        analytics.waitUntilStarted()
    }

    override func tearDown() {
        customerIO.clearIdentify()
        super.tearDown()
    }

    open func overrideDependencies() {}
}
