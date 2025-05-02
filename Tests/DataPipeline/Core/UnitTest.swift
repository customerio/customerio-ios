@testable import CioAnalytics
@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
import SharedTests

/// Base class for unit testing within the module, extending `UnitTestBase` with setup and utilities
/// specific to module components. Ideal for isolated tests of individual functions and classes.
open class UnitTest: SharedTests.UnitTestBase<CustomerIO> {
    public var dataPipelineConfigOptions: DataPipelineConfigOptions!

    // Use this `CustomerIO` instance when invoking `CustomerIOInstance` functions in unit tests.
    // This ensures convenience and consistency across unit tests, and guarantees the correct instance is used for testing.
    var customerIO: CustomerIO!
    var analytics: Analytics!

    override open func setUp() {
        setUp(modifySdkConfig: nil)
    }

    override open func setUp(enableLogs: Bool = false, sdkConfig: SdkConfig? = nil) {
        setUp(enableLogs: enableLogs, modifySdkConfig: nil)
    }

    open func setUp(
        enableLogs: Bool = false,
        cdpApiKey: String? = nil,
        modifySdkConfig: ((SDKConfigBuilder) -> Void)?
    ) {
        let sdkConfigBuilder = SDKConfigBuilder(cdpApiKey: cdpApiKey ?? testCdpApiKey)
        // set sdk log level to debug if logs are enabled
        if enableLogs {
            sdkConfigBuilder.logLevel(.debug)
        }
        // disable auto add destination to prevent tests from sending data to server
        sdkConfigBuilder.autoAddCustomerIODestination(false)
        modifySdkConfig?(sdkConfigBuilder)

        let (sdkConfig, moduleConfig) = sdkConfigBuilder.build()
        dataPipelineConfigOptions = moduleConfig

        super.setUp(sdkConfig: sdkConfig)
    }

    override open func setUpDependencies() {
        super.setUpDependencies()

        // Mock date util so the "Date now" is a the same between our tests and the app so comparing Date objects in
        // test functions is possible.
        diGraphShared.override(value: dateUtilStub, forType: DateUtil.self)
    }

    override open func initializeSDKComponents() -> CustomerIO? {
        // setup implementation instance for unit tests
        let implementation = DataPipeline.setUpSharedInstanceForUnitTest(
            implementation: DataPipelineImplementation(diGraph: diGraphShared, moduleConfig: dataPipelineConfigOptions),
            config: dataPipelineConfigOptions
        )

        // setup shared instance with desired implementation for unit tests
        customerIO = CustomerIO.setUpSharedInstanceForUnitTest(implementation: implementation)

        // wait for analytics queue to start emitting events
        analytics = implementation.analytics
        analytics.waitUntilStarted()

        return customerIO
    }

    override open func deleteAllPersistentData() {
        analytics.storage.hardReset(doYouKnowHowToUseThis: true)
        super.deleteAllPersistentData()
    }

    override open func cleanupTestEnvironment() {
        super.cleanupTestEnvironment()
        Analytics.removeActiveWriteKey(dataPipelineConfigOptions.cdpApiKey)
        CustomerIO.resetTestEnvironment()
    }
}
