@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class LoggerTest: UnitTest {
    private var logger: Logger!
    private let systemLoggerMock = SystemLoggerMock()

    override func setUp() {
        super.setUp()

        logger = LoggerImpl(logger: systemLoggerMock)
    }

    func test_all_givenNoneLogLevel_expectNothingShouldBeLogged() {
        let dispatcherMock = DispatcherMock()
        logger.setLogLevel(.none)
        logger.setLogDispatcher(dispatcherMock.closure)

        logger.debug("Test debug message")
        logger.info("Test info message")
        logger.error("Test error message")

        XCTAssertFalse(systemLoggerMock.mockCalled)
        XCTAssertFalse(dispatcherMock.hasInvocations())
    }

    func test_allWithTag_givenNoneLogLevel_expectNothingShouldBeLogged() {
        let dispatcherMock = DispatcherMock()
        logger.setLogLevel(.none)
        logger.setLogDispatcher(dispatcherMock.closure)

        logger.debug("Test debug message", "anyTag")
        logger.info("Test info message", "anyTag")
        logger.error("Test error message", "anyTag", nil)

        XCTAssertFalse(systemLoggerMock.mockCalled)
        XCTAssertFalse(dispatcherMock.hasInvocations())
    }

    func test_all_givenErrorLogLevel_expectOnlyErrorLog() {
        logger.setLogLevel(.error)

        logger.debug("Test debug message")
        logger.info("Test info message")
        let errorMessage = "Test error message"
        logger.error(errorMessage)

        XCTAssertEqual(systemLoggerMock.logCallsCount, 1)
        XCTAssertEqual(systemLoggerMock.logReceivedInvocations.first?.level, .error)
        XCTAssertEqual(systemLoggerMock.logReceivedInvocations.first?.message, errorMessage)
    }

    func test_allWithTag_givenErrorLogLevel_expectOnlyErrorLog() {
        logger.setLogLevel(.error)

        logger.debug("Test debug message", "MyTag")
        logger.info("Test info message", "MyTag")
        logger.error("Test error message", "MyTag", nil)

        XCTAssertEqual(systemLoggerMock.logCallsCount, 1)
        XCTAssertEqual(systemLoggerMock.logReceivedInvocations.first?.level, .error)
        XCTAssertEqual(systemLoggerMock.logReceivedInvocations.first?.message, "[MyTag] Test error message")
    }

    func test_allWithTagAndError_givenErrorLogLevel_expectOnlyErrorLog() {
        let error = NSError(
            domain: "io.customer",
            code: 12,
            userInfo: [NSLocalizedDescriptionKey: "Localized error"]
        )
        logger.setLogLevel(.error)

        logger.debug("Test debug message", "MyTag")
        logger.info("Test info message", "MyTag")
        logger.error("Test error message", "MyTag", error)

        XCTAssertEqual(systemLoggerMock.logCallsCount, 1)
        XCTAssertEqual(systemLoggerMock.logReceivedInvocations.first?.level, .error)
        XCTAssertEqual(systemLoggerMock.logReceivedInvocations.first?.message, "[MyTag] Test error message Error: Localized error")
    }

    func test_allWithDispatcher_givenErrorLogLevel_expectOnlyErrorLog() {
        let dispatcherMock = DispatcherMock()
        logger.setLogLevel(.error)
        logger.setLogDispatcher(dispatcherMock.closure)

        logger.debug("Test debug message")
        logger.info("Test info message")
        let errorMessage = "Test error message"
        logger.error(errorMessage)

        XCTAssertEqual(dispatcherMock.inovcationsCount(), 1)
        let invocations = dispatcherMock.invocations(for: .error)
        XCTAssertEqual(invocations.first?.level, .error)
        XCTAssertEqual(invocations.first?.message, errorMessage)
    }

    func test_all_givenInfoLogLevel_expectOnlyErrorLog() {
        logger.setLogLevel(.info)

        logger.debug("Test debug message")
        let infoMessage = "Test info message"
        logger.info(infoMessage)
        let errorMessage = "Test error message"
        logger.error(errorMessage)

        XCTAssertEqual(systemLoggerMock.logCallsCount, 2)

        XCTAssertEqual(systemLoggerMock.logReceivedInvocations[0].level, .info)
        XCTAssertEqual(systemLoggerMock.logReceivedInvocations[0].message, infoMessage)

        XCTAssertEqual(systemLoggerMock.logReceivedInvocations[1].level, .error)
        XCTAssertEqual(systemLoggerMock.logReceivedInvocations[1].message, errorMessage)
    }

    func test_allWithTag_givenInfoLogLevel_expectOnlyErrorLog() {
        logger.setLogLevel(.info)

        logger.debug("Test debug message", "SomeTag")
        logger.info("Test info message", "Tag")
        logger.error("Test error message", "MyTag", nil)

        XCTAssertEqual(systemLoggerMock.logCallsCount, 2)

        XCTAssertEqual(systemLoggerMock.logReceivedInvocations[0].level, .info)
        XCTAssertEqual(systemLoggerMock.logReceivedInvocations[0].message, "[Tag] Test info message")

        XCTAssertEqual(systemLoggerMock.logReceivedInvocations[1].level, .error)
        XCTAssertEqual(systemLoggerMock.logReceivedInvocations[1].message, "[MyTag] Test error message")
    }

    func test_allWithDispatcher_givenInfoLogLevel_expectOnlyErrorLog() {
        let dispatcherMock = DispatcherMock()
        logger.setLogLevel(.info)
        logger.setLogDispatcher(dispatcherMock.closure)

        logger.debug("Test debug message")
        let infoMessage = "Test info message"
        logger.info(infoMessage)
        let errorMessage = "Test error message"
        logger.error(errorMessage)

        XCTAssertEqual(dispatcherMock.inovcationsCount(), 2)

        let infoInvocation = dispatcherMock.invocations(for: .info)
        XCTAssertEqual(infoInvocation.first?.level, .info)
        XCTAssertEqual(infoInvocation.first?.message, infoMessage)

        let errorInvocation = dispatcherMock.invocations(for: .error)
        XCTAssertEqual(errorInvocation.first?.level, .error)
        XCTAssertEqual(errorInvocation.first?.message, errorMessage)
    }

    func test_all_givenDebugLogLevel_expectOnlyErrorLog() {
        logger.setLogLevel(.debug)

        let debugMessage = "Test debug message"
        logger.debug(debugMessage)
        let infoMessage = "Test info message"
        logger.info(infoMessage)
        let errorMessage = "Test error message"
        logger.error(errorMessage)

        XCTAssertEqual(systemLoggerMock.logCallsCount, 3)

        XCTAssertEqual(systemLoggerMock.logReceivedInvocations[0].level, .debug)
        XCTAssertEqual(systemLoggerMock.logReceivedInvocations[0].message, debugMessage)

        XCTAssertEqual(systemLoggerMock.logReceivedInvocations[1].level, .info)
        XCTAssertEqual(systemLoggerMock.logReceivedInvocations[1].message, infoMessage)

        XCTAssertEqual(systemLoggerMock.logReceivedInvocations[2].level, .error)
        XCTAssertEqual(systemLoggerMock.logReceivedInvocations[2].message, errorMessage)
    }

    func test_allWithTag_givenDebugLogLevel_expectOnlyErrorLog() {
        logger.setLogLevel(.debug)

        logger.debug("Test debug message", "SomeTag")
        logger.info("Test info message", "Tag")
        logger.error("Test error message", "MyTag", nil)

        XCTAssertEqual(systemLoggerMock.logCallsCount, 3)

        XCTAssertEqual(systemLoggerMock.logReceivedInvocations[0].level, .debug)
        XCTAssertEqual(systemLoggerMock.logReceivedInvocations[0].message, "[SomeTag] Test debug message")

        XCTAssertEqual(systemLoggerMock.logReceivedInvocations[1].level, .info)
        XCTAssertEqual(systemLoggerMock.logReceivedInvocations[1].message, "[Tag] Test info message")

        XCTAssertEqual(systemLoggerMock.logReceivedInvocations[2].level, .error)
        XCTAssertEqual(systemLoggerMock.logReceivedInvocations[2].message, "[MyTag] Test error message")
    }

    func test_allWithDispatcher_givenDebugLogLevel_expectOnlyErrorLog() {
        let dispatcherMock = DispatcherMock()
        logger.setLogLevel(.debug)
        logger.setLogDispatcher(dispatcherMock.closure)

        let debugMessage = "Test debug message"
        logger.debug(debugMessage)
        let infoMessage = "Test info message"
        logger.info(infoMessage)
        let errorMessage = "Test error message"
        logger.error(errorMessage)

        XCTAssertEqual(dispatcherMock.inovcationsCount(), 3)

        let debugInvocation = dispatcherMock.invocations(for: .debug)
        XCTAssertEqual(debugInvocation.first?.level, .debug)
        XCTAssertEqual(debugInvocation.first?.message, debugMessage)

        let infoInvocation = dispatcherMock.invocations(for: .info)
        XCTAssertEqual(infoInvocation.first?.level, .info)
        XCTAssertEqual(infoInvocation.first?.message, infoMessage)

        let errorInvocation = dispatcherMock.invocations(for: .error)
        XCTAssertEqual(errorInvocation.first?.level, .error)
        XCTAssertEqual(errorInvocation.first?.message, errorMessage)
    }
}

class DispatcherMock {
    struct Invocation {
        let level: CioLogLevel
        let message: String
    }

    private(set) var invocations: [Invocation] = []

    var closure: (CioLogLevel, String) -> Void {
        { [weak self] level, message in
            self?.invocations.append(Invocation(level: level, message: message))
        }
    }

    func invocations(for level: CioLogLevel) -> [Invocation] {
        invocations.filter { $0.level == level }
    }

    func inovcationsCount() -> Int {
        invocations.count
    }

    func hasInvocations() -> Bool {
        !invocations.isEmpty
    }
}
