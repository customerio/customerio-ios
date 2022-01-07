import Foundation

enum DateFormat: String {
    case hourMinuteSecond = "HH:mm:ss"
}

extension Date {
    static func fromFormat(_ format: DateFormat, string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = format.rawValue
        return formatter.date(from: string)
    }

    func addMinutes(_ minutes: Int) -> Date {
        let calendar = Calendar(identifier: .iso8601)

        return calendar.date(byAdding: DateComponents(minute: minutes),
                             to: self)!
    }

    func minusMinutes(_ minutes: Int) -> Date {
        let calendar = Calendar(identifier: .iso8601)

        return calendar.date(byAdding: DateComponents(minute: -minutes),
                             to: self)!
    }

    var hasPassed: Bool {
        Date() > self
    }
}
