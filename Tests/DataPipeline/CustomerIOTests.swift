@testable import CioDataPipelines
@testable import CioInternalCommon
import XCTest

class CustomerIOTests: IntegrationTest {
    private let outputter = AccumulatorLogOutputter()

    override open func setUpDependencies() {
        super.setUpDependencies()

        let logger = StandardLogger(logLevel: .debug, outputter: outputter)
        diGraphShared.override(value: logger, forType: SdkCommonLogger.self)
        DataPipeline.resetTestEnvironment()
    }

    override func initializeSDKComponents() -> CustomerIO? {
        super.initializeSDKComponents()
        DataPipeline.resetTestEnvironment()
        return nil
    }

    func test_initialize_expectCoreInitLogs() {
        outputter.clear()

        let config = SDKConfigBuilder(cdpApiKey: .random)
            .logLevel(.debug)
            .build()
        CustomerIO.initialize(withConfig: config)

        let allMessages = outputter.messages
        let message1Index = allMessages.firstIndex {
            (CioLogLevel.debug, "[\(Tags.Init)] Creating new instance of CustomerIO SDK version: \(SdkVersion.version)...") == $0
        } ?? -1
        let message2Index = allMessages.firstIndex {
            (CioLogLevel.info, "[\(Tags.Init)] CustomerIO SDK is initialized and ready to use") == $0
        } ?? -1
        XCTAssert(message1Index >= 0) // SDK Init message must be found
        XCTAssert(message1Index < message2Index) // SDK init complete message must be found and be after init arrives

//        XCTAssertEqual(1, mockLogger.coreSdkInitStartCallsCount)
//        XCTAssertEqual(1, mockLogger.coreSdkInitSuccessCallsCount)
    }

    func test_initialize_expectModuleInitLogs() {
        outputter.clear()

        let config = SDKConfigBuilder(cdpApiKey: .random)
            .logLevel(.debug)
            .build()
        CustomerIO.initialize(withConfig: config)

        let moduleName = "DataPipeline"
        let allMessages = outputter.messages
        let message1Index = allMessages.firstIndex {
            (CioLogLevel.debug, "[\(Tags.Init)] Initializing SDK module \(moduleName)...") == $0
        } ?? -1
        let message2Index = allMessages.firstIndex {
            (CioLogLevel.info, "[\(Tags.Init)] CustomerIO \(moduleName) module is initialized and ready to use") == $0
        } ?? -1
        XCTAssert(message1Index >= 0) // Module Init message must be found
        XCTAssert(message1Index < message2Index) // Module init complete message must be found and be after init arrives
        
//        XCTAssertEqual(1, mockLogger.moduleInitStartCallsCount)
//        XCTAssertEqual(1, mockLogger.moduleInitSuccessCallsCount)
    }
}
