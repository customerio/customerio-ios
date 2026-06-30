@testable import CioDataPipelines
import Foundation
import Testing

@Suite("AggregationRuleset decoding")
struct AggregationRulesetTests {
    // MARK: - Full JSON decode

    @Test func fullRuleset_allFieldsDecodeCorrectly() throws {
        let json = """
        {
          "filters": [
            { "eventType": "track", "name": "page_viewed" }
          ],
          "rateLimits": [
            { "eventType": "track", "name": "button_clicked", "windowSeconds": 3600, "scope": "device" }
          ],
          "rules": null
        }
        """
        let ruleset = try decode(json)

        let filter = try #require(ruleset.filters?.first)
        #expect(filter.eventType == "track")
        #expect(filter.name == "page_viewed")

        let rl = try #require(ruleset.rateLimits?.first)
        #expect(rl.eventType == "track")
        #expect(rl.name == "button_clicked")
        #expect(rl.windowSeconds == 3600)
        #expect(rl.scope == .device)
    }

    // MARK: - Tolerant parsing

    @Test func filterEntry_missingRequiredField_isSkipped() throws {
        let json = #"{ "filters": [{ "name": "ev" }] }"#
        let ruleset = try decode(json)
        #expect(ruleset.filters?.isEmpty == true)
    }

    @Test func rateLimitEntry_missingScope_isSkipped() throws {
        let json = #"{ "rateLimits": [{ "eventType": "track", "name": "ev", "windowSeconds": 60 }] }"#
        let ruleset = try decode(json)
        #expect(ruleset.rateLimits?.isEmpty == true)
    }

    @Test func rateLimitEntry_unknownScope_isSkipped() throws {
        let json = #"{ "rateLimits": [{ "eventType": "track", "name": "ev", "windowSeconds": 60, "scope": "workspace" }] }"#
        let ruleset = try decode(json)
        #expect(ruleset.rateLimits?.isEmpty == true)
    }

    @Test func partiallyInvalidEntries_validOnesRetained() throws {
        let json = """
        {
          "rateLimits": [
            { "eventType": "track", "name": "bad" },
            { "eventType": "track", "name": "good", "windowSeconds": 30, "scope": "profile" }
          ]
        }
        """
        let ruleset = try decode(json)
        #expect(ruleset.rateLimits?.count == 1)
        #expect(ruleset.rateLimits?.first?.name == "good")
    }

    // MARK: - Nullable / absent arrays

    @Test func nullRules_doesNotThrow() throws {
        _ = try decode(#"{ "rules": null }"#)
    }

    @Test func absentFiltersAndRateLimits_areNil() throws {
        let ruleset = try decode(#"{}"#)
        #expect(ruleset.filters == nil)
        #expect(ruleset.rateLimits == nil)
    }

    // MARK: - Helpers

    private func decode(_ json: String) throws -> AggregationRuleset {
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(AggregationRuleset.self, from: data)
    }
}
