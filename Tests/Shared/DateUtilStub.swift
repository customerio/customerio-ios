import Common
import Foundation

public class DateUtilStub: DateUtil {
    public var givenNow: Date = Date.fromFormat(.iso8601noMilliseconds, string: "2022-01-01T01:01:01-0000")!

    public init() {}

    public var now: Date {
        givenNow
    }
}
