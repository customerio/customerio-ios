import Foundation

extension Date {
    var epochNoMilliseconds: TimeInterval {
        timeIntervalSince1970.rounded()
    }
}
