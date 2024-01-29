@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
@testable import Segment
import SharedTests

class UnitTest: SharedTests.UnitTest {
    public var dataPipelineModuleConfig: DataPipelineConfigOptions!
    public var enableLogs: Bool = false

    // Use this `CustomerIO` instance when invoking `CustomerIOInstance` functions in unit tests.
    // This ensures convenience and consistency across unit tests, and guarantees the correct instance is used for testing.
    open var customerIO: CustomerIO!
    open var analytics: Analytics!

    override func setUp() {
        setUp(modifyModuleConfig: nil)
    }

    override func setUp(enableLogs: Bool = false, siteId: String? = nil, modifySdkConfig: ((inout SdkConfig) -> Void)?) {
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
        modifyModuleConfig?(&newModuleConfig)
        dataPipelineModuleConfig = newModuleConfig

        super.setUp(enableLogs: enableLogs, siteId: siteId, modifySdkConfig: modifySdkConfig)
    }

    override func setUpDependencies() {
        super.setUpDependencies()

        diGraph.override(value: dateUtilStub, forType: DateUtil.self)
    }

    override func initializeSDKComponents() -> CustomerIO? {
        // creates CustomerIO instance and set necessary values for testing
        let implementation = DataPipeline.createAndSetSharedTestInstance(diGraphShared: diGraphShared, config: dataPipelineModuleConfig)

        // creates CustomerIO instance and set necessary values for testing
        customerIO = CustomerIO(implementation: implementation, diGraph: diGraph)
        customerIO.setDebugLogsEnabled(enableLogs)

        // wait for analytics queue to start emitting events
        analytics = customerIO.analytics
        analytics.waitUntilStarted()

        return customerIO
    }

    override func deleteAllFiles() {
        analytics.storage.hardReset(doYouKnowHowToUseThis: true)
        super.deleteAllFiles()
    }

    override func resetTestInstances() {
        DataPipeline.resetSharedTestInstance()
        super.resetTestInstances()
    }
}
