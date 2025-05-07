@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class SdkInitializationLoggerTest: UnitTest {
    private let loggerMock = LoggerMock()
    var initLogger: SdkInitializationLogger!

    override func setUp() {
        super.setUp()

        initLogger = SdkInitializationLoggerImpl(logger: loggerMock)
    }

    override func tearDown() {
        initLogger = nil
        initLogger = nil
        super.tearDown()
    }

    func test_coreSdkInitStart_logsExpectedMessage() {
        let version = SdkVersion.version
        initLogger.coreSdkInitStart()

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Init")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Creating new instance of CustomerIO SDK version: \(version)..."
        )
    }

    func test_coreSdkInitSuccess_logsExpectedMessage() {
        initLogger.coreSdkInitSuccess()

        XCTAssertEqual(loggerMock.infoReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.infoReceivedInvocations.first?.tag, "Init")
        XCTAssertEqual(
            loggerMock.infoReceivedInvocations.first?.message,
            "CustomerIO SDK is initialized and ready to use"
        )
    }

    func test_moduleInitStart_logsWithModuleName() {
        initLogger.moduleInitStart("MyModule")

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Init")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Initializing SDK module MyModule..."
        )
    }

    func test_moduleInitSuccess_logsWithModuleName() {
        initLogger.moduleInitSuccess("PushModule")

        XCTAssertEqual(loggerMock.infoReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.infoReceivedInvocations.first?.tag, "Init")
        XCTAssertEqual(
            loggerMock.infoReceivedInvocations.first?.message,
            "CustomerIO PushModule module is initialized and ready to use"
        )
    }
}
