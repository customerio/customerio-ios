@testable import CioMessagingInApp
import Foundation
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
        // `#"\."#` in a raw string is a single backslash followed by a dot: the pattern
        // as it exists in memory after JSON decoding, for a "contains
        // dashboard.account.settings" rule.
        let message = Message(pageRule: #"^(.*dashboard\.account\.settings.*)$"#)
        XCTAssertTrue(message.doesPageRuleMatch(route: "dashboard.account.settings"))
    }

    func test_doesPageRuleMatch_givenEqualsRuleWithEscapedDots_expectMatchExactDottedRoute() {
        let message = Message(pageRule: #"^(dashboard\.account\.settings)$"#)
        XCTAssertTrue(message.doesPageRuleMatch(route: "dashboard.account.settings"))
    }

    // MARK: - doesPageRuleMatch across the JSON transport boundary

    // The tests above hand Message a Swift literal, which skips the step where the escape
    // could be lost. The backend delivers the rule inside the message's `properties` JSON,
    // where a literal dot is written `\\.` on the wire and decodes to `\.` in memory.
    // Building the message from real JSON pins the whole path: wire escaping -> decoded
    // pattern -> ICU literal-dot match.
    func test_doesPageRuleMatch_givenRouteRuleDecodedFromJson_expectMatchDottedRoute() throws {
        // Raw string, so `\\.` is the two characters JSON uses to encode one backslash.
        let json = #"""
        {
          "gist": {
            "campaignId": "test-campaign",
            "routeRuleApple": "^(.*dashboard\\.account\\.settings.*)$"
          }
        }
        """#
        let properties = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let message = Message(messageId: .random, queueId: .random, priority: nil, properties: properties)

        // Decoding leaves one backslash before each dot, so ICU treats the dots as literal.
        XCTAssertEqual(message.cleanPageRule, #"^(.*dashboard\.account\.settings.*)$"#)
        XCTAssertTrue(message.doesPageRuleMatch(route: "dashboard.account.settings"))
        // The escaped dots must stay literal rather than acting as the "any character" wildcard.
        XCTAssertFalse(message.doesPageRuleMatch(route: "dashboardXaccountXsettings"))
    }

    // MARK: - cleanPageRule preserves escaped metacharacters

    func test_cleanPageRule_givenEscapedDots_expectDotsNotCorruptedToSlash() {
        let message = Message(pageRule: #"^(.*dashboard\.account\.settings.*)$"#)
        XCTAssertEqual(message.cleanPageRule, #"^(.*dashboard\.account\.settings.*)$"#)
    }

    // cleanPageRule is a pass-through: it must preserve every backslash, whatever follows it.
    // This is an identity check on the property, not a claim that the backend sends
    // consecutive backslashes.
    func test_cleanPageRule_givenConsecutiveBackslashes_expectEveryBackslashPreserved() {
        let message = Message(pageRule: #"^(.*dashboard\\.account\\.settings.*)$"#)
        XCTAssertEqual(message.cleanPageRule, #"^(.*dashboard\\.account\\.settings.*)$"#)
    }
}
