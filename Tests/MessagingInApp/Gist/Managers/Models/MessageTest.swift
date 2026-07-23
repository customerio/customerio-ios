@testable import CioMessagingInApp
import XCTest

class MessageTest: XCTestCase {
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

    // MARK: - doesPageRuleMatch with escaped regex metacharacters

    // A route target containing "." is delivered as a regex with the dots escaped
    // (e.g. "\." for a literal dot). cleanPageRule must pass the regex through
    // untouched so these escapes survive; corrupting "\" would make any dotted
    // route impossible to match.
    func test_doesPageRuleMatch_givenContainsRuleWithEscapedDots_expectMatchDottedRoute() {
        // `#"\."#` in a raw string is a backslash followed by a dot, exactly as the
        // route rule arrives over the wire for a "contains dashboard.account.settings" rule.
        let message = Message(pageRule: #"^(.*dashboard\.account\.settings.*)$"#)
        XCTAssertTrue(message.doesPageRuleMatch(route: "dashboard.account.settings"))
    }

    func test_doesPageRuleMatch_givenEqualsRuleWithEscapedDots_expectMatchExactDottedRoute() {
        let message = Message(pageRule: #"^(dashboard\.account\.settings)$"#)
        XCTAssertTrue(message.doesPageRuleMatch(route: "dashboard.account.settings"))
    }

    // MARK: - cleanPageRule preserves escaped metacharacters

    func test_cleanPageRule_givenEscapedDots_expectDotsNotCorruptedToSlash() {
        let message = Message(pageRule: #"^(.*dashboard\.account\.settings.*)$"#)
        XCTAssertEqual(message.cleanPageRule, #"^(.*dashboard\.account\.settings.*)$"#)
    }

    // Some rules arrive with the backslash itself escaped (two backslashes before
    // each dot). cleanPageRule must still leave every backslash intact.
    func test_cleanPageRule_givenDoubleEscapedDots_expectBackslashesNotCorruptedToSlash() {
        let message = Message(pageRule: #"^(.*dashboard\\.account\\.settings.*)$"#)
        XCTAssertEqual(message.cleanPageRule, #"^(.*dashboard\\.account\\.settings.*)$"#)
    }
}
