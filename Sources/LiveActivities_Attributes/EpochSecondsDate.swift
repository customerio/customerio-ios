import Foundation

/// Use this instead of a bare `Date` for any date field in your Live Activity `Attributes` or
/// `ContentState` (e.g. an estimated arrival time).
///
/// It encodes and decodes as a JSON number of **seconds** since 1970 (UTC), which is the format
/// Customer.io sends and expects — so the value your widget shows matches what a Customer.io push
/// delivers. Wrap your date at the call site (`EpochSecondsDate(someDate)`) and read it back via
/// ``date`` (or ``value``).
///
/// > Note: A round trip is exact to the whole second; sub-second precision is not preserved.
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
