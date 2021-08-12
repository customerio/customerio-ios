import Foundation

internal extension DateFormatter {
    // Example of string this generates: "2021-02-14T15:09:02-06:00"
    static var iso8601: DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return dateFormatter
    }
}
