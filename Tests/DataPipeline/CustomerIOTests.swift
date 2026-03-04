import XCTest

@testable import CioDataPipelines
@testable import CioInternalCommon

class CustomerIOTests: IntegrationTest {
    private let mockLogger = SdkCommonLoggerMock()

    override open func setUpDependencies() {
        super.setUpDependencies()

        mockCollection.add(mock: mockLogger)

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

    func test_initialize_withOptionalModule_expectModuleInitializedAndLogged() {
        let optionalModule = CustomerIOTestsMockModule(name: "OptionalModule")

        let config = SDKConfigBuilder(cdpApiKey: .random)
            .addModule(optionalModule)
            .build()
        CustomerIO.initialize(withConfig: config)

        XCTAssertEqual(optionalModule.initializeCallCount, 1)
        XCTAssertTrue(mockLogger.moduleInitStartReceivedInvocations.contains("OptionalModule"))
        XCTAssertTrue(mockLogger.moduleInitSuccessReceivedInvocations.contains("OptionalModule"))
    }

    func test_initialize_withMultipleOptionalModules_expectAllInitializedInOrder() {
        let module1 = CustomerIOTestsMockModule(name: "First")
        let module2 = CustomerIOTestsMockModule(name: "Second")

        let config = SDKConfigBuilder(cdpApiKey: .random)
            .addModule(module1)
            .addModule(module2)
            .build()
        CustomerIO.initialize(withConfig: config)

        XCTAssertEqual(module1.initializeCallCount, 1)
        XCTAssertEqual(module2.initializeCallCount, 1)
        XCTAssertEqual(mockLogger.moduleInitStartReceivedInvocations.count, 3) // DataPipeline + First + Second
        XCTAssertEqual(mockLogger.moduleInitStartReceivedInvocations[1], "First")
        XCTAssertEqual(mockLogger.moduleInitStartReceivedInvocations[2], "Second")
        XCTAssertEqual(mockLogger.moduleInitSuccessReceivedInvocations[1], "First")
        XCTAssertEqual(mockLogger.moduleInitSuccessReceivedInvocations[2], "Second")
    }
}

// MARK: - Mock module for CustomerIO initialize tests

private final class CustomerIOTestsMockModule: CustomerIOModule {
    let moduleName: String
    private(set) var initializeCallCount = 0

    init(name: String) {
        self.moduleName = name
    }

    func initialize() {
        initializeCallCount += 1
    }
}
