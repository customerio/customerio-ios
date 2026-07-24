@testable import CioAnalytics
@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
import SyncSqlCipher
import Testing

@Suite("EventPolicyPlugin")
struct EventPolicyPluginTests {
    let storage: StorageManager
    let engine: EventPolicyEngine
    let plugin: EventPolicyPlugin

    init() throws {
        let db = try Database(path: ":memory:", key: "testkey", walMode: false)
        self.storage = StorageManager(db: db)
        try storage.runMigrations()
        self.engine = EventPolicyEngine(storage: storage)
        self.plugin = EventPolicyPlugin(engine: engine, storage: storage)
    }

    // MARK: - No ruleset — everything passes

    @Test func noRuleset_trackPassesThrough() {
        let event = TrackEvent(event: "any_event", properties: nil)
        #expect(plugin.track(event: event) != nil)
    }

    @Test func noRuleset_screenPassesThrough() {
        let event = ScreenEvent(title: "Home", category: nil)
        #expect(plugin.screen(event: event) != nil)
    }

    @Test func noRuleset_identifyPassesThrough() {
        let event = IdentifyEvent(userId: "user-1", traits: nil)
        #expect(plugin.identify(event: event) != nil)
    }

    // MARK: - Track filter

    @Test func track_filteredEvent_returnsNil() {
        engine.load(ruleset: filterRuleset(eventType: "track", name: "page_viewed"))
        let event = TrackEvent(event: "page_viewed", properties: nil)
        #expect(plugin.track(event: event) == nil)
    }

    @Test func track_unfilteredEvent_returnsEvent() {
        engine.load(ruleset: filterRuleset(eventType: "track", name: "page_viewed"))
        let event = TrackEvent(event: "button_clicked", properties: nil)
        #expect(plugin.track(event: event) != nil)
    }

    @Test func track_wildcardFilter_blocksAllTrackEvents() {
        engine.load(ruleset: filterRuleset(eventType: "track", name: "*"))
        #expect(plugin.track(event: TrackEvent(event: "ev_a", properties: nil)) == nil)
        #expect(plugin.track(event: TrackEvent(event: "ev_b", properties: nil)) == nil)
    }

    // MARK: - Screen filter

    @Test func screen_filteredEvent_returnsNil() {
        engine.load(ruleset: filterRuleset(eventType: "screen", name: "Home"))
        let event = ScreenEvent(title: "Home", category: nil)
        #expect(plugin.screen(event: event) == nil)
    }

    @Test func screen_unfilteredEvent_returnsEvent() {
        engine.load(ruleset: filterRuleset(eventType: "screen", name: "Home"))
        let event = ScreenEvent(title: "Settings", category: nil)
        #expect(plugin.screen(event: event) != nil)
    }

    // MARK: - Identify filter

    @Test func identify_wildcardFilter_returnsNil() {
        engine.load(ruleset: filterRuleset(eventType: "identify", name: "*"))
        let event = IdentifyEvent(userId: "user-1", traits: nil)
        #expect(plugin.identify(event: event) == nil)
    }

    // MARK: - Config persistence

    @Test func update_withAggregationRules_persistsConfigToStorage() throws {
        let settings = try settingsWithFilters([("track", "page_viewed")])
        plugin.update(settings: settings, type: .initial)
        let config = try storage.getAggregationConfig()
        #expect(config != nil)
    }

    @Test func update_withAggregationRules_persistedConfigDecodesCorrectly() throws {
        let settings = try settingsWithFilters([("track", "page_viewed")])
        plugin.update(settings: settings, type: .initial)

        let config = try #require(try storage.getAggregationConfig())
        let ruleset = try #require(try? JSONDecoder().decode(AggregationRuleset.self, from: Data(config.payload.utf8)))
        #expect(ruleset.filters?.first?.eventType == "track")
        #expect(ruleset.filters?.first?.name == "page_viewed")
    }

    @Test func update_withoutAggregationRules_doesNotWriteToStorage() throws {
        let settings = try settingsWithoutRules()
        plugin.update(settings: settings, type: .initial)
        let config = try storage.getAggregationConfig()
        #expect(config == nil)
    }

    @Test func update_serverRemovesRules_deletesPreviouslyPersistedConfig() throws {
        try plugin.update(settings: settingsWithFilters([("track", "page_viewed")]), type: .initial)
        #expect(try storage.getAggregationConfig() != nil)

        try plugin.update(settings: settingsWithoutRules(), type: .refresh)
        #expect(try storage.getAggregationConfig() == nil)
    }

    @Test func update_refresh_overwritesPreviouslyPersistedConfig() throws {
        try plugin.update(settings: settingsWithFilters([("track", "page_viewed")]), type: .initial)
        try plugin.update(settings: settingsWithFilters([("screen", "Home")]), type: .refresh)

        let config = try #require(try storage.getAggregationConfig())
        let ruleset = try #require(try? JSONDecoder().decode(AggregationRuleset.self, from: Data(config.payload.utf8)))
        #expect(ruleset.filters?.first?.eventType == "screen")
        #expect(ruleset.filters?.first?.name == "Home")
    }

    // MARK: - Helpers

    private func filterRuleset(eventType: String, name: String) -> AggregationRuleset {
        let json = """
        {"filters":[{"eventType":"\(eventType)","name":"\(name)"}]}
        """
        return try! JSONDecoder().decode(AggregationRuleset.self, from: json.data(using: .utf8)!)
    }

    private func settingsWithFilters(_ filters: [(eventType: String, name: String)]) throws -> Settings {
        let filtersJSON = filters
            .map { "{\"eventType\":\"\($0.eventType)\",\"name\":\"\($0.name)\"}" }
            .joined(separator: ",")
        return try settings(aggregationRulesJSON: "{\"filters\":[\(filtersJSON)]}")
    }

    private func settingsWithoutRules() throws -> Settings {
        try settings(aggregationRulesJSON: nil)
    }

    private func settings(aggregationRulesJSON: String?) throws -> Settings {
        let rulesFragment = aggregationRulesJSON.map { "\"aggregationRules\": \($0)," } ?? ""
        let json = """
        {
            "integrations": {
                "Customer.io Data Pipelines": {
                    \(rulesFragment)
                    "apiKey": "test-key"
                }
            }
        }
        """
        return try JSONDecoder().decode(Settings.self, from: json.data(using: .utf8)!)
    }
}
