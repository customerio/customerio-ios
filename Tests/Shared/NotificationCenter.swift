import Foundation
import XCTest
#if canImport(UserNotifications)
import UserNotifications

final class KeyedArchiver: NSKeyedArchiver {
    override func decodeObject(forKey _: String) -> Any { "" }
    override func decodeInt64(forKey key: String) -> Int64 { 0 }
}

public extension UNNotificationResponse {
    // Hack to get an instance of `UNNotificationResponse`. This is mostly for API tests
    // when an instance is needed. For unit tests, it's to not involve `UNNotificationResponse` at all.
    // Parse parts of `UNNotificationResponse` that you need and test that function instead.
    // Hack help: https://onmyway133.com/posts/how-to-mock-unnotificationresponse-in-unit-tests/
    static var testInstance: UNNotificationResponse {
        // OK to use try! as it's utility code used by tests and is rarely edited.
        // swiftlint:disable:next force_try
        try! XCTUnwrap(UNNotificationResponse(coder: KeyedArchiver()))
    }
}
#endif
