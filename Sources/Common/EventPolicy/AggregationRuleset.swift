import Foundation

public enum RuleScope: String, Codable, Sendable {
    case profile
    case device

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RuleScope(rawValue: raw) ?? .profile
    }
}

public struct FilterEntry: Codable, Sendable {
    public let eventType: String
    public let name: String
    public let scope: RuleScope

    enum CodingKeys: String, CodingKey { case eventType, name, scope }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventType = try c.decode(String.self, forKey: .eventType)
        name      = try c.decode(String.self, forKey: .name)
        scope     = try c.decodeIfPresent(RuleScope.self, forKey: .scope) ?? .profile
    }
}

public struct RateLimitEntry: Codable, Sendable {
    public let eventType: String
    public let name: String
    public let windowSeconds: Int
    public let scope: RuleScope

    enum CodingKeys: String, CodingKey { case eventType, name, windowSeconds, scope }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventType     = try c.decode(String.self, forKey: .eventType)
        name          = try c.decode(String.self, forKey: .name)
        windowSeconds = try c.decode(Int.self,    forKey: .windowSeconds)
        scope         = try c.decodeIfPresent(RuleScope.self, forKey: .scope) ?? .profile
    }
}

public struct AggregationRuleset: Codable, Sendable {
    public let filters: [FilterEntry]?
    public let rateLimits: [RateLimitEntry]?
    // rules reserved for next aggregation phase
}