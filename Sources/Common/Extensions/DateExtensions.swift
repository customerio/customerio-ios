import Foundation

public enum DateFormat: String {
    case hourMinuteSecond = "HH:mm:ss"
    case iso8601noMilliseconds = "yyyy-MM-dd'T'HH:mm:ssZ"
    case iso8601WithMilliseconds
}

extension Date {
    static func fromFormat(_ format: DateFormat, string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = format.rawValue
        return formatter.date(from: string)
    }

    public func string(format: DateFormat) -> String {
        if format == .iso8601WithMilliseconds {
            return formatToIso8601WithMilliseconds()
        }
        let formatter = DateFormatter()
        formatter.dateFormat = format.rawValue
        return formatter.string(from: self)
    }

    func formatToIso8601WithMilliseconds() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: self)
    }

    public static func fromIso8601WithMilliseconds(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        // Try with fractional seconds first
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        // Fall back to without fractional seconds for dates like "2026-02-09T12:26:42Z"
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    func add(_ value: Double, _ unit: Calendar.Component) -> Date {
        add(Int(value), unit)
    }

    func add(_ value: Int, _ unit: Calendar.Component) -> Date {
        let calendar = Calendar(identifier: .iso8601)

        var dateComponents = DateComponents()
        dateComponents.setValue(value, for: unit)

        return calendar.date(byAdding: dateComponents, to: self)!
    }

    func subtract(_ value: Double, _ unit: Calendar.Component) -> Date {
        subtract(Int(value), unit)
    }

    func subtract(_ value: Int, _ unit: Calendar.Component) -> Date {
        let calendar = Calendar(identifier: .iso8601)

        var dateComponents = DateComponents()
        dateComponents.setValue(-value, for: unit)

        return calendar.date(byAdding: dateComponents, to: self)!
    }

    func isOlderThan(_ other: Date) -> Bool {
        timeIntervalSince1970 < other.timeIntervalSince1970
    }

    var hasPassed: Bool {
        Date() > self
    }

    // When decoding code to and from JSON, we lose milliseconds from the Date() objects.
    // This can be difficult for unit testing because you might have to compare two
    // identical Date() objects but one of the instances has the milliseconds removed.
    // Use this to construct a new Date() object without the milliseconds to use in tests.
    static var nowNoMilliseconds: Date {
        let nowString = Date().string(format: .iso8601noMilliseconds)

        return Date.fromFormat(.iso8601noMilliseconds, string: nowString)!
    }

    /// Converts Date to milliseconds since 1970 (Unix epoch in milliseconds)
    public var millisecondsSince1970: Double {
        timeIntervalSince1970 * 1000
    }

    /// Creates a Date from milliseconds since 1970 (Unix epoch in milliseconds)
    public static func fromMillisecondsSince1970(_ milliseconds: Double) -> Date {
        Date(timeIntervalSince1970: milliseconds / 1000)
    }

    /// Adds milliseconds to the current date
    public func addingMilliseconds(_ milliseconds: Double) -> Date {
        Date(timeIntervalSince1970: timeIntervalSince1970 + (milliseconds / 1000))
    }
}
