@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class LoggerTest: UnitTest {
    private var logger: Logger!
    private var outputter: AccumulatorLogOutputter!

    override func setUp() {
        super.setUp()

        outputter = AccumulatorLogOutputter()
        logger = LoggerImpl(outputter: outputter)
    }

    func testLogLevelNoneWithoutTags() {
        outputter.clear()
        logger.setLogLevel(.none)

        logger.debug("Test debug message")
        logger.info("Test info message")
        logger.error("Test error message")

        XCTAssertFalse(outputter.hasMessages)
    }

    func testLogLevelNoneWithTags() {
        outputter.clear()
        logger.setLogLevel(.none)

        logger.debug("Test debug message", "anyTag")
        logger.info("Test info message", "anyTag")
        logger.error("Test error message", "anyTag", nil)

        
        XCTAssertFalse(outputter.hasMessages)
    }

    func testLogLevelErrorWithoutTags() {
        outputter.clear()
        logger.setLogLevel(.error)

        logger.debug("Test debug message")
        logger.info("Test info message")
        let errorMessage = "Test error message"
        logger.error(errorMessage)

        XCTAssertTrue(outputter.hasMessages)
        XCTAssertEqual(outputter.messages.count, 1)
        XCTAssertEqual(outputter.debugMessages.count, 0)
        XCTAssertEqual(outputter.infoMessages.count, 0)
        XCTAssertEqual(outputter.errorMessages.count, 1)

        let first = outputter.messages.first
        XCTAssertEqual(first?.0, .error)
        XCTAssertEqual(first?.1, errorMessage)
    }

    func testLogLevelErrorWithTags() {
        outputter.clear()
        logger.setLogLevel(.error)

        logger.debug("Test debug message", "DebugTag")
        logger.info("Test info message", "InfoTag")
        logger.error("Test error message", "ErrorTag")

        XCTAssertTrue(outputter.hasMessages)
        XCTAssertEqual(outputter.messages.count, 1)
        XCTAssertEqual(outputter.debugMessages.count, 0)
        XCTAssertEqual(outputter.infoMessages.count, 0)
        XCTAssertEqual(outputter.errorMessages.count, 1)

        let first = outputter.messages.first
        XCTAssertEqual(first?.0, .error)
        XCTAssertEqual(first?.1, "[ErrorTag] Test error message")
    }

    func testLogLevelErrorWithTagsAndError() {
        outputter.clear()
        
        let error = NSError(
            domain: "io.customer",
            code: 12,
            userInfo: [NSLocalizedDescriptionKey: "Localized error"]
        )
        logger.setLogLevel(.error)

        logger.debug("Test debug message", "DebugTag")
        logger.info("Test info message", "InfoTag")
        logger.error("Test error message", "ErrorTag", error)

        
        XCTAssertTrue(outputter.hasMessages)
        XCTAssertEqual(outputter.messages.count, 1)
        XCTAssertEqual(outputter.debugMessages.count, 0)
        XCTAssertEqual(outputter.infoMessages.count, 0)
        XCTAssertEqual(outputter.errorMessages.count, 1)

        let first = outputter.messages.first
        XCTAssertEqual(first?.0, .error)
        XCTAssertEqual(first?.1, "[ErrorTag] Test error message Error: Localized error")
    }

    func testLogLevelInfoWithoutTags() {
        outputter.clear()
        logger.setLogLevel(.info)

        logger.debug("Test debug message")
        let infoMessage = "Test info message"
        logger.info(infoMessage)
        let errorMessage = "Test error message"
        logger.error(errorMessage)

        
        XCTAssertTrue(outputter.hasMessages)
        XCTAssertEqual(outputter.messages.count, 2)
        XCTAssertEqual(outputter.debugMessages.count, 0)
        XCTAssertEqual(outputter.infoMessages.count, 1)
        XCTAssertEqual(outputter.errorMessages.count, 1)

        let first = outputter.messages[0]
        XCTAssertEqual(first.0, .info)
        XCTAssertEqual(first.1, infoMessage)

        let second = outputter.messages[1]
        XCTAssertEqual(second.0, .error)
        XCTAssertEqual(second.1, errorMessage)
    }

    func testLogLevelInfoWithTags() {
        outputter.clear()
        logger.setLogLevel(.info)

        logger.debug("Test debug message", "DebugTag")
        logger.info("Test info message", "InfoTag")
        logger.error("Test error message", "ErrorTag")
        
        XCTAssertTrue(outputter.hasMessages)
        XCTAssertEqual(outputter.messages.count, 2)
        XCTAssertEqual(outputter.debugMessages.count, 0)
        XCTAssertEqual(outputter.infoMessages.count, 1)
        XCTAssertEqual(outputter.errorMessages.count, 1)

        let first = outputter.messages[0]
        XCTAssertEqual(first.0, .info)
        XCTAssertEqual(first.1, "[InfoTag] Test info message")

        let second = outputter.messages[1]
        XCTAssertEqual(second.0, .error)
        XCTAssertEqual(second.1, "[ErrorTag] Test error message")
    }

    func testLogLevelDebugWithoutTags() {
        
        outputter.clear()
        logger.setLogLevel(.debug)

        let debugMessage = "Test debug message"
        logger.debug(debugMessage)
        let infoMessage = "Test info message"
        logger.info(infoMessage)
        let errorMessage = "Test error message"
        logger.error(errorMessage)

        
        XCTAssertTrue(outputter.hasMessages)
        XCTAssertEqual(outputter.messages.count, 3)
        XCTAssertEqual(outputter.debugMessages.count, 1)
        XCTAssertEqual(outputter.infoMessages.count, 1)
        XCTAssertEqual(outputter.errorMessages.count, 1)

        let first = outputter.messages[0]
        XCTAssertEqual(first.0, .debug)
        XCTAssertEqual(first.1, debugMessage)
        XCTAssertEqual(outputter.firstDebugMessage, debugMessage)

        let second = outputter.messages[1]
        XCTAssertEqual(second.0, .info)
        XCTAssertEqual(second.1, infoMessage)
        XCTAssertEqual(outputter.firstInfoMessage, infoMessage)

        let third = outputter.messages[2]
        XCTAssertEqual(third.0, .error)
        XCTAssertEqual(third.1, errorMessage)
        XCTAssertEqual(outputter.firstErrorMessage, errorMessage)
    }

    func testLogLevelDebugWithTags() {
        logger.setLogLevel(.debug)

        logger.debug("Test debug message", "DebugTag")
        logger.info("Test info message", "InfoTag")
        logger.error("Test error message", "ErrorTag")

        
        XCTAssertTrue(outputter.hasMessages)
        XCTAssertEqual(outputter.messages.count, 3)
        XCTAssertEqual(outputter.debugMessages.count, 1)
        XCTAssertEqual(outputter.infoMessages.count, 1)
        XCTAssertEqual(outputter.errorMessages.count, 1)

        let first = outputter.messages[0]
        let debugMessage = "[DebugTag] Test debug message"
        XCTAssertEqual(first.0, .debug)
        XCTAssertEqual(first.1, debugMessage)
        XCTAssertEqual(outputter.firstDebugMessage, debugMessage)

        let second = outputter.messages[1]
        let infoMessage = "[InfoTag] Test info message"
        XCTAssertEqual(second.0, .info)
        XCTAssertEqual(second.1, infoMessage)
        XCTAssertEqual(outputter.firstInfoMessage, infoMessage)

        let third = outputter.messages[2]
        let errorMessage = "[ErrorTag] Test error message"
        XCTAssertEqual(third.0, .error)
        XCTAssertEqual(third.1, errorMessage)
        XCTAssertEqual(outputter.firstErrorMessage, errorMessage)
    }
}

//class DispatcherMock {
//    struct Invocation {
//        let level: CioLogLevel
//        let message: String
//    }
//
//    private(set) var invocations: [Invocation] = []
//
//    var closure: (CioLogLevel, String) -> Void {
//        { [weak self] level, message in
//            self?.invocations.append(Invocation(level: level, message: message))
//        }
//    }
//
//    func invocations(for level: CioLogLevel) -> [Invocation] {
//        invocations.filter { $0.level == level }
//    }
//
//    func inovcationsCount() -> Int {
//        invocations.count
//    }
//
//    func hasInvocations() -> Bool {
//        !invocations.isEmpty
//    }
//}
