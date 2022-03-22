import CioTracking
import Foundation

public class DateUtilStub: DateUtil {
    public var givenNow: Date = .init()

    public init() {}

    public var now: Date {
        givenNow
    }
}
