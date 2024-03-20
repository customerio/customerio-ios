@testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class ManualPushHandlingIntegrationTests: IntegrationTest {
    private let pushClickHandler = PushClickHandlerMock()

    // The manual push click handling functions are currently housed in `MessagingPushImplementation`. Get instance for integration test.
    private var messagingPush: MessagingPushImplementation? {
        notNilOrFail(MessagingPush.shared.implementation as? MessagingPushImplementation)
    }

    override func setUp() {
        super.setUp { config in
            config.autoTrackPushEvents(false) // we are testing manual push tracking. Disable automatic push tracking feature.
        }

        DIGraphShared.shared.override(value: pushClickHandler, forType: PushClickHandler.self)
    }

    // MARK: manual push click handling

    func test_manualPushClick_expectHandlePushClick() {
        let givenDeliveryId = String.random
        let givenDeviceToken = String.random

        let cioPush = PushNotificationStub.getPushSentFromCIO(deliveryId: givenDeliveryId, deviceToken: givenDeviceToken)

        // The order matters of push click handling
        pushClickHandler.assertWillHandleDeepLinkLast(for: cioPush)

        messagingPush?.manualPushClickHandling(push: cioPush)

        pushClickHandler.assertHandledPushClick(for: cioPush)
    }
}
