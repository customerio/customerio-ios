import Foundation

extension Date {
    func addDaysToCurrentDate(days: Int) -> Date? {
        guard let newDate = Calendar.current.date(byAdding: .day, value: days, to: self) else {
            // return current date
            return Date()
        }
        return newDate
    }
}
