@testable import CioInternalCommon
import Foundation
import SyncSqlCipher
import Testing

@Suite("EventPolicyEngine")
struct EventPolicyEngineTests {
    let storage: StorageManager
    let engine: EventPolicyEngine

    init() throws {
        let db = try Database(path: ":memory:", key: "testkey", walMode: false)
        storage = StorageManager(db: db)
        try storage.runMigrations()
        engine = EventPolicyEngine(storage: storage)
    }

    // MARK: - No ruleset

    @Test func noRuleset_alwaysAllows() {
        #expect(engine.shouldAllow(eventType: "track", name: "any_event", now: 0) == true)
    }

    // MARK: - Filter rules

    @Test func filter_blocksMatchingEvent() {
        engine.load(ruleset: ruleset(filters: [filter("track", "page_viewed")]))
        #expect(engine.shouldAllow(eventType: "track", name: "page_viewed", now: 0) == false)
    }

    @Test func filter_allowsNonMatchingEvent() {
        engine.load(ruleset: ruleset(filters: [filter("track", "page_viewed")]))
        #expect(engine.shouldAllow(eventType: "track", name: "button_clicked", now: 0) == true)
    }

    @Test func filter_wildcardBlocksAllEventsOfType() {
        engine.load(ruleset: ruleset(filters: [filter("track", "*")]))
        #expect(engine.shouldAllow(eventType: "track", name: "anything", now: 0) == false)
        #expect(engine.shouldAllow(eventType: "track", name: "something_else", now: 0) == false)
    }

    @Test func filter_wildcardDoesNotBlockDifferentEventType() {
        engine.load(ruleset: ruleset(filters: [filter("track", "*")]))
        #expect(engine.shouldAllow(eventType: "screen", name: "Home", now: 0) == true)
    }

    // MARK: - Rate-limit rules

    @Test func rateLimit_firstCallAllowed() {
        engine.load(ruleset: ruleset(rateLimits: [rateLimit("track", "btn", 3600)]))
        #expect(engine.shouldAllow(eventType: "track", name: "btn", now: 1_000) == true)
    }

    @Test func rateLimit_secondCallWithinWindowBlocked() {
        engine.load(ruleset: ruleset(rateLimits: [rateLimit("track", "btn", 3600)]))
        _ = engine.shouldAllow(eventType: "track", name: "btn", now: 1_000)
        #expect(engine.shouldAllow(eventType: "track", name: "btn", now: 1_001) == false)
    }

    @Test func rateLimit_callAfterWindowAllowed() {
        engine.load(ruleset: ruleset(rateLimits: [rateLimit("track", "btn", 3600)]))
        _ = engine.shouldAllow(eventType: "track", name: "btn", now: 1_000)
        #expect(engine.shouldAllow(eventType: "track", name: "btn", now: 1_000 + 3600 + 1) == true)
    }

    @Test func rateLimit_wildcardMatchesAllEventsOfType() {
        engine.load(ruleset: ruleset(rateLimits: [rateLimit("track", "*", 3600)]))
        _ = engine.shouldAllow(eventType: "track", name: "any_event", now: 1_000)
        #expect(engine.shouldAllow(eventType: "track", name: "any_event", now: 1_001) == false)
    }

    // MARK: - Filter takes priority over rate-limit

    @Test func filter_evaluatedBeforeRateLimit() {
        engine.load(ruleset: ruleset(
            filters: [filter("track", "ev")],
            rateLimits: [rateLimit("track", "ev", 0)]  // windowSeconds=0 would allow via rate-limit alone
        ))
        #expect(engine.shouldAllow(eventType: "track", name: "ev", now: 0) == false)
    }

    // MARK: - Ruleset reload

    @Test func loadNilRuleset_clearsRules() {
        engine.load(ruleset: ruleset(filters: [filter("track", "ev")]))
        engine.load(ruleset: nil)
        #expect(engine.shouldAllow(eventType: "track", name: "ev", now: 0) == true)
    }

    // MARK: - Helpers

    private func filter(_ eventType: String, _ name: String) -> FilterEntry {
        decode("{\"eventType\":\"\(eventType)\",\"name\":\"\(name)\"}")
    }

    private func rateLimit(_ eventType: String, _ name: String, _ windowSeconds: Int) -> RateLimitEntry {
        decode("{\"eventType\":\"\(eventType)\",\"name\":\"\(name)\",\"windowSeconds\":\(windowSeconds)}")
    }

    private func ruleset(filters: [FilterEntry]? = nil, rateLimits: [RateLimitEntry]? = nil) -> AggregationRuleset {
        var parts: [String] = []
        if let f = filters {
            let items = f.map { "{\"eventType\":\"\($0.eventType)\",\"name\":\"\($0.name)\"}" }
            parts.append("\"filters\":[\(items.joined(separator: ","))]")
        }
        if let rl = rateLimits {
            let items = rl.map { "{\"eventType\":\"\($0.eventType)\",\"name\":\"\($0.name)\",\"windowSeconds\":\($0.windowSeconds)}" }
            parts.append("\"rateLimits\":[\(items.joined(separator: ","))]")
        }
        return decode("{\(parts.joined(separator: ","))}")
    }

    private func decode<T: Decodable>(_ json: String) -> T {
        try! JSONDecoder().decode(T.self, from: json.data(using: .utf8)!)
    }
}