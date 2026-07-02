import Foundation

/// A `Date` wrapper that is `Codable` as an epoch-millisecond number.
///
/// Live Activity content-state and attributes are decoded on-device by ActivityKit
/// using its **own** `JSONDecoder` when a backend push arrives — the SDK cannot inject a
/// `dateDecodingStrategy` there. To keep the wire format unambiguous across the local CDP
/// event path (`LiveActivityReporter`) and the server push path (ActivityKit), every date
/// field on a template's `Attributes`/`ContentState` is represented by this type instead of
/// a bare `Date`.
///
/// - Decodes from a JSON number interpreted as milliseconds since 1970 (UTC).
/// - Encodes to a JSON number of milliseconds since 1970 (UTC).
///
/// This matches the Android SDK convention (epoch ms) and the value the reporter's
/// `payloadEncoder` produces, so a round trip is lossless to the millisecond.
public struct EpochMillisDate: Codable, Hashable, Sendable {
    /// The wrapped date value.
    public var date: Date

    public init(_ date: Date) {
        self.date = date
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let millis = try container.decode(Int64.self)
        self.date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let millis = Int64((date.timeIntervalSince1970 * 1000).rounded())
        try container.encode(millis)
    }
}

public extension EpochMillisDate {
    /// Convenience accessor for the wrapped `Date`.
    var value: Date { date }
}
