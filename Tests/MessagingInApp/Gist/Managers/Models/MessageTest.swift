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

    // MARK: - doesHavePageRule

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

    // MARK: - doesPageRuleMatch

    func test_doesPageRuleMatch_givenNoRouteRule_expectFalse() {
        let message = Message(pageRule: nil)
        let result = message.doesPageRuleMatch(route: "home")
        XCTAssertFalse(result)
    }

    func test_doesPageRuleMatch_givenContainsRegexPattern_expectMatchRoutesThatContain() {
        let message = Message(pageRule: "^(.*home.*)$")
        XCTAssertTrue(message.doesPageRuleMatch(route: "home"))
        XCTAssertTrue(message.doesPageRuleMatch(route: "foohomebar"))
        XCTAssertTrue(message.doesPageRuleMatch(route: "homebar"))
        XCTAssertTrue(message.doesPageRuleMatch(route: "foohome"))
        XCTAssertFalse(message.doesPageRuleMatch(route: "hom"))
    }

    func test_doesPageRuleMatch_givenEqualsRegexPattern_expectMatchRoutesThatEqual() {
        let message = Message(pageRule: "^(home)$")
        XCTAssertTrue(message.doesPageRuleMatch(route: "home"))
        XCTAssertFalse(message.doesPageRuleMatch(route: "foohomebar"))
        XCTAssertFalse(message.doesPageRuleMatch(route: "homebar"))
        XCTAssertFalse(message.doesPageRuleMatch(route: "foohome"))
        XCTAssertFalse(message.doesPageRuleMatch(route: "hom"))
    }

    func test_doesPageRuleMatch_givenWildcardRouteRule_expectAlwaysTrue() {
        let message = Message(pageRule: "^(.*)$")
        XCTAssertTrue(message.doesPageRuleMatch(route: "home"))
        XCTAssertTrue(message.doesPageRuleMatch(route: "foohomebar"))
        XCTAssertTrue(message.doesPageRuleMatch(route: "homebar"))
        XCTAssertTrue(message.doesPageRuleMatch(route: "foohome"))
        XCTAssertTrue(message.doesPageRuleMatch(route: "hom"))
    }

    func test_doesPageRuleMatch_givenInvalidRegex_expectFalse() {
        let message = Message(pageRule: "[")
        let result = message.doesPageRuleMatch(route: "home")
        XCTAssertFalse(result)
    }
}
