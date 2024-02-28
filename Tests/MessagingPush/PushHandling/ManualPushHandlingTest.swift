@testable import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class ManualPushHandlingIntegrationTests: IntegrationTest {
    private let customerIOMock = CustomerIOInstanceMock()

    // The manual push click handling functions are currently housed in `MessagingPushImplementation`. Get instance for integration test.
    private var messagingPush: MessagingPushImplementation? {
        notNilOrFail(MessagingPush.shared.implementation as? MessagingPushImplementation)
    }

    override func setUp() {
        super.setUp { config in
            config.autoTrackPushMetricEvents = .delivered // we are testing manual push tracking. Disable opened automatic push tracking feature.
        }

        diGraph.override(value: customerIOMock, forType: CustomerIOInstance.self)
    }

    // MARK: opened push metrics

    func test_expectTrackOpenedMetrics() {
        let givenDeliveryId = String.random
        let givenDeviceToken = String.random

        let cioPush = PushNotificationStub.getPushSentFromCIO(deliveryId: givenDeliveryId, deviceToken: givenDeviceToken)

        messagingPush?.manualPushClickHandling(push: cioPush)

        XCTAssertEqual(customerIOMock.trackMetricCallsCount, 1)
        XCTAssertEqual(customerIOMock.trackMetricReceivedArguments?.deliveryID, givenDeliveryId)
        XCTAssertEqual(customerIOMock.trackMetricReceivedArguments?.deviceToken, givenDeviceToken)
    }
}
