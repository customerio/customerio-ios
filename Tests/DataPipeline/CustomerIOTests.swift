@testable import CioInternalCommon
@testable import CioDataPipelines
import XCTest

class CustomerIOTests: IntegrationTest {
    private let mockLogger = SdkInitializationLoggerMock()

    override open func setUpDependencies() {
        super.setUpDependencies()

        diGraphShared.override(value: mockLogger, forType: SdkInitializationLogger.self)
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
