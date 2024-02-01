@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
@testable import Segment
import SharedTests

/// Base class for unit testing within the module, extending `UnitTestBase` with setup and utilities
/// specific to module components. Ideal for isolated tests of individual functions and classes.
open class UnitTest: SharedTests.UnitTestBase<CustomerIO> {
    public var dataPipelineConfigOptions: DataPipelineConfigOptions!
    public var enableLogs: Bool = false

    // Use this `CustomerIO` instance when invoking `CustomerIOInstance` functions in unit tests.
    // This ensures convenience and consistency across unit tests, and guarantees the correct instance is used for testing.
    var customerIO: CustomerIO!
    var analytics: Analytics!

    override open func setUp() {
        setUp(modifyModuleConfig: nil)
    }

    override open func setUp(enableLogs: Bool = false, siteId: String? = nil, modifySdkConfig: ((inout SdkConfig) -> Void)?) {
        setUp(enableLogs: enableLogs, siteId: siteId, modifySdkConfig: modifySdkConfig, modifyModuleConfig: nil)
    }

    open func setUp(
        enableLogs: Bool = false,
        siteId: String? = nil,
        writeKey: String? = nil,
        modifySdkConfig: ((inout SdkConfig) -> Void)? = nil,
        modifyModuleConfig: ((inout DataPipelineConfigOptions) -> Void)?
    ) {
        // store value so it can be reused later when SDK is initialized
        self.enableLogs = enableLogs

        var newModuleConfig = DataPipelineConfigOptions.Factory.create(writeKey: writeKey ?? testWriteKey)
        // disable auto add destination to prevent tests from sending data to server
        newModuleConfig.autoAddCustomerIODestination = false
        modifyModuleConfig?(&newModuleConfig)
        dataPipelineConfigOptions = newModuleConfig

        super.setUp(enableLogs: enableLogs, siteId: siteId, modifySdkConfig: modifySdkConfig)
    }

    override open func setUpDependencies() {
        super.setUpDependencies()

        // Mock date util so the "Date now" is a the same between our tests and the app so comparing Date objects in
        // test functions is possible.
        diGraphShared.override(value: dateUtilStub, forType: DateUtil.self)
        diGraph.override(value: dateUtilStub, forType: DateUtil.self)
    }

    override open func initializeSDKComponents() -> CustomerIO? {
        // setup implementation instance for unit tests
        let implementation = DataPipeline.setUpSharedInstanceForUnitTest(
            implementation: DataPipelineImplementation(diGraph: diGraphShared, moduleConfig: dataPipelineConfigOptions),
            config: dataPipelineConfigOptions
        )

        // setup shared instance with desired implementation for unit tests
        customerIO = CustomerIO.setUpSharedInstanceForUnitTest(implementation: implementation, diGraph: diGraph)
        customerIO.setDebugLogsEnabled(enableLogs)

        // wait for analytics queue to start emitting events
        analytics = implementation.analytics
        analytics.waitUntilStarted()

        return customerIO
    }

    override open func deleteAllPersistantData() {
        analytics.storage.hardReset(doYouKnowHowToUseThis: true)
        super.deleteAllPersistantData()
    }

    override open func cleanupTestEnvironment() {
        super.cleanupTestEnvironment()
        CustomerIO.resetTestEnvironment()
    }
}
