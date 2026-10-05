@testable import CioMessagingPushFCM
import XCTest

class MessagingPushFCMTests: XCTestCase {
    private class RecordingMessagingPushFCM: MessagingPushFCM {
        var registeredTokens: [String?] = []

        override func registerDeviceToken(fcmToken: String?) {
            registeredTokens.append(fcmToken)
        }
    }

    func testDidReceiveRegistration_whenInstallationIdIsSet_thenItIsRegistered() {
        let messagingPushFCM = RecordingMessagingPushFCM()

        messagingPushFCM.messaging("", didReceiveRegistration: "fid-value")

        XCTAssertEqual(messagingPushFCM.registeredTokens, ["fid-value"])
    }

    func testDidReceiveRegistration_whenInstallationIdIsNil_thenNothingIsRegistered() {
        let messagingPushFCM = RecordingMessagingPushFCM()

        messagingPushFCM.messaging("", didReceiveRegistration: nil)

        XCTAssertTrue(messagingPushFCM.registeredTokens.isEmpty)
    }
}
