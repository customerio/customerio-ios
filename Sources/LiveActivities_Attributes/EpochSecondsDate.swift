import Foundation

/// A `Date` wrapper that is `Codable` as an epoch-**second** number.
///
/// Live Activity content-state and attributes are decoded on-device by ActivityKit
/// using its **own** `JSONDecoder` when a backend push arrives — the SDK cannot inject a
/// `dateDecodingStrategy` there. To keep the wire format unambiguous across the local CDP
/// event path (`LiveActivityReporter`) and the server push path (ActivityKit), every date
/// field on a template's `Attributes`/`ContentState` is represented by this type instead of
/// a bare `Date`.
///
/// - Decodes from a JSON number interpreted as seconds since 1970 (UTC).
/// - Encodes to a JSON number of seconds since 1970 (UTC).
///
/// Seconds is the Customer.io backend contract for content-state timestamps; the reporter's
/// `payloadEncoder` produces the same representation, so a round trip is lossless to the second.
public struct EpochSecondsDate: Codable, Hashable, Sendable {
    /// The wrapped date value.
    public var date: Date

    public init(_ date: Date) {
        self.date = date
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let seconds = try container.decode(Int64.self)
        self.date = Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let seconds = Int64(date.timeIntervalSince1970.rounded())
        try container.encode(seconds)
    }
}

public extension EpochSecondsDate {
    /// Convenience accessor for the wrapped `Date`.
    var value: Date { date }
}
