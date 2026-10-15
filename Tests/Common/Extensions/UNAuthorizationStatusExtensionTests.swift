import Foundation
import Testing
import UserNotifications

@testable import CioInternalCommon

struct UNAuthorizationStatusExtensionTests {
    // MARK: cioLogName

    @Test
    func test_cioLogName_expectIOSOwnNameForEachStatus() {
        #expect(UNAuthorizationStatus.notDetermined.cioLogName == "notDetermined")
        #expect(UNAuthorizationStatus.denied.cioLogName == "denied")
        #expect(UNAuthorizationStatus.authorized.cioLogName == "authorized")
        #expect(UNAuthorizationStatus.provisional.cioLogName == "provisional")
    }

    @Test
    func test_cioLogName_givenStatusWithoutName_expectRawValue() {
        let unnamed = UNAuthorizationStatus(rawValue: 99)!

        #expect(unnamed.cioLogName == "other(99)")
    }
}
