import Foundation

enum RuleScope: String, Codable, Sendable {
    case profile
    case device

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RuleScope(rawValue: raw) ?? .profile
    }
}

struct FilterEntry: Codable, Sendable {
    let eventType: String
    let name: String
    let scope: RuleScope

    enum CodingKeys: String, CodingKey { case eventType, name, scope }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventType = try c.decode(String.self, forKey: .eventType)
        name      = try c.decode(String.self, forKey: .name)
        scope     = try c.decodeIfPresent(RuleScope.self, forKey: .scope) ?? .profile
    }
}

struct RateLimitEntry: Codable, Sendable {
    let eventType: String
    let name: String
    let windowSeconds: Int
    let scope: RuleScope

    enum CodingKeys: String, CodingKey { case eventType, name, windowSeconds, scope }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventType     = try c.decode(String.self, forKey: .eventType)
        name          = try c.decode(String.self, forKey: .name)
        windowSeconds = try c.decode(Int.self,    forKey: .windowSeconds)
        scope         = try c.decodeIfPresent(RuleScope.self, forKey: .scope) ?? .profile
    }
}

struct AggregationRuleset: Codable, Sendable {
    let filters: [FilterEntry]?
    let rateLimits: [RateLimitEntry]?
    // rules reserved for next aggregation phase
}
