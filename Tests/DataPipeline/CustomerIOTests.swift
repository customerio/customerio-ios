@testable import CioDataPipelines
@testable import CioInternalCommon
import XCTest

class CustomerIOTests: IntegrationTest {
    private let mockLogger = SdkCommonLoggerMock()

    override open func setUpDependencies() {
        super.setUpDependencies()

        diGraphShared.override(value: mockLogger, forType: SdkCommonLogger.self)
        DataPipeline.resetTestEnvironment()
    }

    override func initializeSDKComponents() -> CustomerIO? {
        super.initializeSDKComponents()
        DataPipeline.resetTestEnvironment()
        return nil
    }

    func test_initialize_expectCoreInitLogs() {
        CustomerIO.initialize(withConfig: SDKConfigBuilder(cdpApiKey: .random).build())

        XCTAssertEqual(1, mockLogger.coreSdkInitStartCallsCount)
        XCTAssertEqual(1, mockLogger.coreSdkInitSuccessCallsCount)
    }

    func test_initialize_expectModuleInitLogs() {
        CustomerIO.initialize(withConfig: SDKConfigBuilder(cdpApiKey: .random).build())

        XCTAssertEqual(1, mockLogger.moduleInitStartCallsCount)
        XCTAssertEqual(1, mockLogger.moduleInitSuccessCallsCount)
    }
}
