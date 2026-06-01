@testable import CioAnalytics
@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
import SyncSqlCipher
import Testing

@Suite("EventPolicyPlugin")
struct EventPolicyPluginTests {
    let engine: EventPolicyEngine
    let plugin: EventPolicyPlugin

    init() throws {
        let db = try Database(path: ":memory:", key: "testkey", walMode: false)
        let storage = StorageManager(db: db)
        try storage.runMigrations()
        engine = EventPolicyEngine(storage: storage)
        plugin = EventPolicyPlugin(engine: engine)
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

    // MARK: - Helpers

    private func filterRuleset(eventType: String, name: String) -> AggregationRuleset {
        let json = """
        {"filters":[{"eventType":"\(eventType)","name":"\(name)"}]}
        """
        return try! JSONDecoder().decode(AggregationRuleset.self, from: json.data(using: .utf8)!)
    }
}