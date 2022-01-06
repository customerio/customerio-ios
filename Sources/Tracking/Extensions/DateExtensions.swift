import Foundation

public extension Date {
    // When decoding code to and from JSON, we lose milliseconds from the Date() objects.
    // This can be difficult for unit testing because you might have to compare two
    // identical Date() objects but one of the instances has the milliseconds removed.
    // Use this to construct a new Date() object without the milliseconds to use in tests.
    static var nowNoMilliseconds: Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        let nowString = formatter.string(from: Date())

        return formatter.date(from: nowString)!
    }
}
