@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
@testable import SharedTests
import XCTest

/// Extension of `UnitTest` but performs some tasks that sets the environment for integration tests.
/// Unit test classes should have a predictable environment for easier debugging. Integration tests
/// have more SDK code involved and may require some modification to the test environment before tests run.
open class IntegrationTest: UnitTest {
    // Use minimal mocks/stubs in integration tests to closely match production behavior.
    public private(set) var deviceInfoStub: DeviceInfoStub!

    override open func setUpDependencies() {
        super.setUpDependencies()

        // Mock device info since we are running tests, not running the app on a device. Tests crash when trying to
        // execute the code in the real device into implementation.
        deviceInfoStub = DeviceInfoStub()
        diGraphShared.override(value: deviceInfoStub, forType: DeviceInfo.self)
    }

    override open func initializeSDKComponents() -> CustomerIO? {
        // setup shared instance with actual implementation for integration tests
        let implementation = CustomerIO.setUpSharedInstanceForIntegrationTest(
            diGraphShared: diGraphShared, moduleConfig: dataPipelineConfigOptions
        )

        // store shared CustomerIO instance for convenience
        customerIO = CustomerIO.shared

        // wait for analytics queue to start emitting events
        analytics = implementation.analytics
        analytics.waitUntilStarted()

        return customerIO
    }
}
