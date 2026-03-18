import Foundation
import SharedTests
import XCTest

@testable import CioInternalCommon
@testable import CioMessagingPush

class MessagingPushTest: IntegrationTest {
    override func initializeSDKComponents() -> MessagingPushInstance? {
        // We want to manually initialize the module in test functions. So, override this function to disable automatic module initialization.
        nil
    }

    private let pushNotificationCenterRegistrarMock = PushNotificationCenterRegistrarMock()

    override func setUp() {
        super.setUp()

        mockCollection.add(mock: pushNotificationCenterRegistrarMock)

        DIGraphShared.shared.override(
            value: pushNotificationCenterRegistrarMock,
            forType: PushNotificationCenterRegistrar.self
        )
    }

    // MARK: initialize

    func
        test_initialize_givenDefaultModuleConfigOptions_expectActivatePushNotificationCenterRegistrar()
    {
        MessagingPush.initialize()

        XCTAssertEqual(pushNotificationCenterRegistrarMock.activateCallsCount, 1)
    }

    func test_initialize_givenCustomerDisabledAutoTrackPushEvents_expectDoNotActivateRegistrar() {
        MessagingPush.initialize(
            withConfig: MessagingPushConfigBuilder()
                .autoTrackPushEvents(false)
                .build()
        )

        XCTAssertFalse(pushNotificationCenterRegistrarMock.activateCalled)
    }
}
