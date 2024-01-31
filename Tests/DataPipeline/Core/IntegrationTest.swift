@testable import CioDataPipelines
@testable import CioInternalCommon
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

    override open func setUpDependencies() {
        super.setUpDependencies()

        // Mock device info since we are running tests, not running the app on a device. Tests crash when trying to
        // execute the code in the real device into implementation.
        deviceInfoStub = DeviceInfoStub()
        diGraphShared.override(value: deviceInfoStub, forType: DeviceInfo.self)
        diGraph.override(value: deviceInfoStub, forType: DeviceInfo.self)
    }

    override open func initializeSDKComponents() -> CustomerIO? {
        // Because integration tests try to test in an environment that is as to production as possible, we need to
        // initialize the SDK. This is especially important to have the Tracking module setup.
        CustomerIO.setUpSharedTestInstance(diGraphShared: diGraphShared, diGraph: diGraph, moduleConfig: dataPipelineModuleConfig)

        // get shared CustomerIO instance for convenience
        customerIO = CustomerIO.shared

        // wait for analytics queue to start emitting events
        analytics = customerIO.analytics
        analytics.waitUntilStarted()

        return customerIO
    }
}
