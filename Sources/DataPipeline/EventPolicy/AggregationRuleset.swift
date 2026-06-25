import Foundation

enum RuleScope: String, Codable, Sendable {
    case profile
    case device
}

struct FilterEntry: Codable, Sendable {
    let eventType: String
    let name: String
}

struct RateLimitEntry: Codable, Sendable {
    let eventType: String
    let name: String
    let windowSeconds: Int
    let scope: RuleScope
}

struct AggregationRuleset: Codable, Sendable {
    let filters: [FilterEntry]?
    let rateLimits: [RateLimitEntry]?
    // rules reserved for next aggregation phase

    private enum CodingKeys: String, CodingKey { case filters, rateLimits }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filters = try c.decodeIfPresent([Failable<FilterEntry>].self, forKey: .filters)?.compactMap(\.value)
        rateLimits = try c.decodeIfPresent([Failable<RateLimitEntry>].self, forKey: .rateLimits)?.compactMap(\.value)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(filters, forKey: .filters)
        try c.encodeIfPresent(rateLimits, forKey: .rateLimits)
    }
}

private struct Failable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
