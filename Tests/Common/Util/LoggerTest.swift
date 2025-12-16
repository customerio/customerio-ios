@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class LoggerTest: UnitTest {
    private var logger: Logger!
    private var outputter: AccumulatorLogDestination!

    override func setUp() {
        super.setUp()

        outputter = AccumulatorLogDestination()
        logger = StandardLogger(destination: outputter)
    }

    func testLogLevelNoneWithoutTags() {
        outputter.clear()
        logger.logLevel = .none

        logger.debug("Test debug message")
        logger.info("Test info message")
        logger.error("Test error message")

        XCTAssertFalse(outputter.hasMessages)
    }

    func testLogLevelNoneWithTags() {
        outputter.clear()
        logger.logLevel = .none

        logger.debug("Test debug message", "anyTag")
        logger.info("Test info message", "anyTag")
        logger.error("Test error message", "anyTag", nil)

        
        XCTAssertFalse(outputter.hasMessages)
    }

    func testLogLevelErrorWithoutTags() {
        outputter.clear()
        logger.logLevel = .error

        logger.debug("Test debug message")
        logger.info("Test info message")
        let errorMessage = "Test error message"
        logger.error(errorMessage)

        XCTAssertTrue(outputter.hasMessages)
        XCTAssertEqual(outputter.allMessages.count, 1)
        XCTAssertEqual(outputter.debugMessages.count, 0)
        XCTAssertEqual(outputter.infoMessages.count, 0)
        XCTAssertEqual(outputter.errorMessages.count, 1)

        let first = outputter.allMessages.first
        XCTAssertEqual(first?.level, .error)
        XCTAssertEqual(first?.content, errorMessage)
    }

    func testLogLevelErrorWithTags() {
        outputter.clear()
        logger.logLevel = .error

        logger.debug("Test debug message", "DebugTag")
        logger.info("Test info message", "InfoTag")
        logger.error("Test error message", "ErrorTag")

        XCTAssertTrue(outputter.hasMessages)
        XCTAssertEqual(outputter.allMessages.count, 1)
        XCTAssertEqual(outputter.debugMessages.count, 0)
        XCTAssertEqual(outputter.infoMessages.count, 0)
        XCTAssertEqual(outputter.errorMessages.count, 1)

        let first = outputter.allMessages.first
        XCTAssertEqual(first?.level, .error)
        XCTAssertEqual(first?.content, "Test error message")
        XCTAssertEqual(first?.tag, "ErrorTag")
    }

    func testLogLevelErrorWithTagsAndError() {
        outputter.clear()
        
        let error = NSError(
            domain: "io.customer",
            code: 12,
            userInfo: [NSLocalizedDescriptionKey: "Localized error"]
        )
        logger.logLevel = .error

        logger.debug("Test debug message", "DebugTag")
        logger.info("Test info message", "InfoTag")
        logger.error("Test error message", "ErrorTag", error)

        
        XCTAssertTrue(outputter.hasMessages)
        XCTAssertEqual(outputter.allMessages.count, 1)
        XCTAssertEqual(outputter.debugMessages.count, 0)
        XCTAssertEqual(outputter.infoMessages.count, 0)
        XCTAssertEqual(outputter.errorMessages.count, 1)

        let first = outputter.allMessages.first
        XCTAssertEqual(first?.level, .error)
        XCTAssertEqual(first?.content, "Test error message Error: Localized error")
        XCTAssertEqual(first?.tag, "ErrorTag")
    }

    func testLogLevelInfoWithoutTags() {
        outputter.clear()
        logger.logLevel = .info

        logger.debug("Test debug message")
        let infoMessage = "Test info message"
        logger.info(infoMessage)
        let errorMessage = "Test error message"
        logger.error(errorMessage)

        
        XCTAssertTrue(outputter.hasMessages)
        XCTAssertEqual(outputter.allMessages.count, 2)
        XCTAssertEqual(outputter.debugMessages.count, 0)
        XCTAssertEqual(outputter.infoMessages.count, 1)
        XCTAssertEqual(outputter.errorMessages.count, 1)

        let first = outputter.allMessages[0]
        XCTAssertEqual(first.level, .info)
        XCTAssertEqual(first.content, infoMessage)

        let second = outputter.allMessages[1]
        XCTAssertEqual(second.level, .error)
        XCTAssertEqual(second.content, errorMessage)
    }

    func testLogLevelInfoWithTags() {
        outputter.clear()
        logger.logLevel = .info

        logger.debug("Test debug message", "DebugTag")
        logger.info("Test info message", "InfoTag")
        logger.error("Test error message", "ErrorTag")
        
        XCTAssertTrue(outputter.hasMessages)
        XCTAssertEqual(outputter.allMessages.count, 2)
        XCTAssertEqual(outputter.debugMessages.count, 0)
        XCTAssertEqual(outputter.infoMessages.count, 1)
        XCTAssertEqual(outputter.errorMessages.count, 1)

        let first = outputter.allMessages[0]
        XCTAssertEqual(first.level, .info)
        XCTAssertEqual(first.content, "Test info message")
        XCTAssertEqual(first.tag, "InfoTag")

        let second = outputter.allMessages[1]
        XCTAssertEqual(second.level, .error)
        XCTAssertEqual(second.content, "Test error message")
        XCTAssertEqual(second.tag, "ErrorTag")
    }

    func testLogLevelDebugWithoutTags() {
        
        outputter.clear()
        logger.logLevel = .debug

        let debugMessage = "Test debug message"
        logger.debug(debugMessage)
        let infoMessage = "Test info message"
        logger.info(infoMessage)
        let errorMessage = "Test error message"
        logger.error(errorMessage)

        
        XCTAssertTrue(outputter.hasMessages)
        XCTAssertEqual(outputter.allMessages.count, 3)
        XCTAssertEqual(outputter.debugMessages.count, 1)
        XCTAssertEqual(outputter.infoMessages.count, 1)
        XCTAssertEqual(outputter.errorMessages.count, 1)

        let first = outputter.allMessages[0]
        XCTAssertEqual(first.level, .debug)
        XCTAssertEqual(first.content, debugMessage)
        XCTAssertEqual(outputter.firstDebugMessage?.content, debugMessage)

        let second = outputter.allMessages[1]
        XCTAssertEqual(second.level, .info)
        XCTAssertEqual(second.content, infoMessage)
        XCTAssertEqual(outputter.firstInfoMessage?.content, infoMessage)

        let third = outputter.allMessages[2]
        XCTAssertEqual(third.level, .error)
        XCTAssertEqual(third.content, errorMessage)
        XCTAssertEqual(outputter.firstErrorMessage?.content, errorMessage)
    }

    func testLogLevelDebugWithTags() {
        logger.logLevel = .debug

        let debugMessage = "Test debug message"
        logger.debug(debugMessage, "DebugTag")
        let infoMessage = "Test info message"
        logger.info(infoMessage, "InfoTag")
        let errorMessage = "Test error message"
        logger.error(errorMessage, "ErrorTag")

        
        XCTAssertTrue(outputter.hasMessages)
        XCTAssertEqual(outputter.allMessages.count, 3)
        XCTAssertEqual(outputter.debugMessages.count, 1)
        XCTAssertEqual(outputter.infoMessages.count, 1)
        XCTAssertEqual(outputter.errorMessages.count, 1)

        let first = outputter.allMessages[0]
        XCTAssertEqual(first.level, .debug)
        XCTAssertEqual(first.content, debugMessage)
        XCTAssertEqual(outputter.firstDebugMessage?.content, debugMessage)

        let second = outputter.allMessages[1]
        XCTAssertEqual(second.level, .info)
        XCTAssertEqual(second.content, infoMessage)
        XCTAssertEqual(outputter.firstInfoMessage?.content, infoMessage)

        let third = outputter.allMessages[2]
        XCTAssertEqual(third.level, .error)
        XCTAssertEqual(third.content, errorMessage)
        XCTAssertEqual(outputter.firstErrorMessage?.content, errorMessage)
    }
}
