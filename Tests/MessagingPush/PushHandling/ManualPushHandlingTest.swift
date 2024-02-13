@testable import CioInternalCommon
@testable import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class ManualPushHandlingIntegrationTests: IntegrationTest {
    // The manual push click handling functions are currently housed in `MessagingPushImplementation`. Get instance for integration test.
    private var messagingPush: MessagingPushImplementation? {
        notNilOrFail(MessagingPush.shared.implementation as? MessagingPushImplementation)
    }

    private let pushClickHandlerMock = PushClickHandlerMock()

    override func setUp() {
        super.setUp { config in
            config.autoTrackPushEvents = false // we are testing manual push tracking. Disable automatic push tracking feature.
        }

        DIGraphShared.shared.override(value: pushClickHandlerMock, forType: PushClickHandler.self)
    }

    // MARK: opened push metrics

    func test_expectTrackOpenedMetrics() {
        let givenDeliveryId = String.random
        let givenDeviceToken = String.random

        let cioPush = PushNotificationStub.getPushSentFromCIO(deliveryId: givenDeliveryId, deviceToken: givenDeviceToken)

        messagingPush?.manualPushClickHandling(push: cioPush)

        XCTAssertEqual(pushClickHandlerMock.pushClickedCallsCount, 1)
        XCTAssertEqual(pushClickHandlerMock.pushClickedReceivedArguments?.cioDelivery?.id, givenDeliveryId)
        XCTAssertEqual(pushClickHandlerMock.pushClickedReceivedArguments?.cioDelivery?.token, givenDeviceToken)
    }
}
