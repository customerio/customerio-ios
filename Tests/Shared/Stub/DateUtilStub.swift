import CioInternalCommon
import Foundation

public class DateUtilStub: DateUtil {
    // Important that we create a Date with milliseconds as that is what
    // the real implmentation of DateUtil will use. Do not remove milliseconds here.
    public var givenNow: Date = .init()

    public init() {}

    public var now: Date {
        givenNow
    }
}

public extension DateUtilStub {
    // Convenient way to get seconds (removed milliseconds) in tests.
    // Common to use when testing Json since our JsonAdapter removes milliseconds when composing Json strings.
    var nowSeconds: Int {
        Int(now.timeIntervalSince1970)
    }
}
