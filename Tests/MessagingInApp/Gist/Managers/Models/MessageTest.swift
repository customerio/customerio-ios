@testable import CioMessagingInApp
import XCTest

class MessageTest: XCTestCase {
    func test_doesHavePageRule_givenNoRouteRule_expectFalse() {
        let message = Message(messageId: "testMessageId")
        let result = message.doesHavePageRule()
        XCTAssertFalse(result)
    }

    func test_doesHavePageRule_givenRouteRule_expectTrue() {
        let message = Message(messageId: .random, campaignId: .random, pageRule: .random)
        let result = message.doesHavePageRule()
        XCTAssertTrue(result)
    }

    func test_doesHavePageRule_givenEmptyProperties_expectFalse() {
        let message = Message(messageId: "testMessageId", properties: [:])
        let result = message.doesHavePageRule()
        XCTAssertFalse(result)
    }
}
