@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

class MessageTest: UnitTest {
    // MARK: Test getter properties

    func test_elementId_givenInlineMessage_expectGetElementId() {
        let givenElementId = String.random

        let message = Message(messageId: .random, campaignId: .random, elementId: givenElementId)

        XCTAssertEqual(message.elementId, givenElementId)
    }

    func test_elementId_givenModalMessage_expectNil() {
        let message = Message(messageId: .random, campaignId: .random, elementId: nil)

        XCTAssertNil(message.elementId)
    }

    func test_isInlineMessage_givenInlineMessage_expectTrue() {
        let message = Message(messageId: .random, campaignId: .random, elementId: .random)

        XCTAssertTrue(message.isInlineMessage)
    }

    func test_isInlineMessage_givenModalMessage_expectFalse() {
        let message = Message(messageId: .random, campaignId: .random, elementId: nil)

        XCTAssertFalse(message.isInlineMessage)
    }

    func test_isModalMessage_givenInlineMessage_expectFalse() {
        let message = Message(messageId: .random, campaignId: .random, elementId: .random)

        XCTAssertFalse(message.isModalMessage)
    }

    func test_isModalMessage_givenModalMessage_expectTrue() {
        let message = Message(messageId: .random, campaignId: .random, elementId: nil)

        XCTAssertTrue(message.isModalMessage)
    }
}
