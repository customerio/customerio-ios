@testable import CioInternalCommon
@testable import CioMessagingPush
@testable import CioMessagingPushFCM
@testable import CioMessagingPushMocks
import XCTest

class MessagingPushFCMTests: XCTestCase {
    private class RecordingMessagingPushFCM: MessagingPushFCM {
        var registrations: [(token: String?, tokenType: DeviceTokenType)] = []

        override func registerFirebaseDeviceToken(_ deviceToken: String?, tokenType: DeviceTokenType) {
            registrations.append((deviceToken, tokenType))
        }
    }

    override func tearDown() {
        MessagingPush.resetTestEnvironment()
        super.tearDown()
    }

    func testDidReceiveRegistration_whenInstallationIdIsNil_thenNothingIsRegistered() {
        let implementationMock = MessagingPushInstanceMock()
        MessagingPush.setUpSharedInstanceForUnitTest(
            implementation: implementationMock,
            diGraphShared: DIGraphShared.shared,
            config: MessagingPushConfigBuilder().build()
        )

        MessagingPushFCM().messaging("", didReceiveRegistration: nil)

        XCTAssertFalse(implementationMock.registerDeviceTokenCalled)
    }

    func testDidReceiveRegistration_whenCalled_thenRegisteredAsFid() {
        let messagingPushFCM = RecordingMessagingPushFCM()

        messagingPushFCM.messaging("", didReceiveRegistration: "fid-value")

        XCTAssertEqual(messagingPushFCM.registrations.map(\.token), ["fid-value"])
        XCTAssertEqual(messagingPushFCM.registrations.map(\.tokenType), [.fid])
    }

    func testDidReceiveRegistrationToken_whenCalled_thenRegisteredAsToken() {
        let messagingPushFCM = RecordingMessagingPushFCM()

        messagingPushFCM.messaging("", didReceiveRegistrationToken: "fcm-token")

        XCTAssertEqual(messagingPushFCM.registrations.map(\.token), ["fcm-token"])
        XCTAssertEqual(messagingPushFCM.registrations.map(\.tokenType), [.token])
    }
}
