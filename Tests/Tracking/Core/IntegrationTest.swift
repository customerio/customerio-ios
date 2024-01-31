@testable import CioDataPipelines
@testable import CioInternalCommon
@testable import CioTracking
import Foundation
@testable import SharedTests
import XCTest

/**
 Extension of `UnitTest` but performs some tasks that sets the environment for integration tests. Unit test classes should have a predictable environment for easier debugging. Integration tests have more SDK code involved and may require some modification to the test environment before tests run.
 */
open class IntegrationTest: UnitTest {
    // We want to mock/stub as little as possible in our integration tests.
    // This class contains a default set of mocks/stubs that *all* integration tests
    // in the code use.
    public private(set) var deviceInfoStub: DeviceInfoStub!
    // Date util stub is available in UnitTest
    public private(set) var sampleDataFilesUtil: SampleDataFilesUtil!

    override open func setUpDependencies() {
        super.setUpDependencies()

        sampleDataFilesUtil = SampleDataFilesUtil(fileStore: diGraph.fileStorage)

        // Mock date util so the "Date now" is a the same between our tests and the app so comparing Date objects in
        // test functions is possible.
        diGraph.override(value: dateUtilStub, forType: DateUtil.self)

        // Mock device info since we are running tests, not running the app on a device. Tests crash when trying to
        // execute the code in the real device into implementation.
        deviceInfoStub = DeviceInfoStub()
        diGraph.override(value: deviceInfoStub, forType: DeviceInfo.self)
    }

    override open func initializeSDKComponents() -> CustomerIO? {
        // Because integration tests try to test in an environment that is as to production as possible, we need to
        // initialize the SDK. This is especially important to have the Tracking module setup.
        CustomerIO.setUpSharedTestInstance(diGraphShared: diGraphShared, diGraph: diGraph, autoAddCustomerIODestination: false)

        return CustomerIO.shared
    }
}
