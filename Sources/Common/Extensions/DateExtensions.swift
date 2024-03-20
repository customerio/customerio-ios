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
}
