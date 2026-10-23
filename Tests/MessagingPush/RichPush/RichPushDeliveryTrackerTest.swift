@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class RichPushDeliveryTrackerTest: UnitTest {
    private let httpClientMock = HttpClientMock()

    override func setUp() {
        super.setUp()
        mockCollection.add(mocks: [httpClientMock])
    }

    func test_trackMetric_givenNoApiHost_expectRequestToRegionHost() {
        let tracker = RichPushDeliveryTrackerImpl(httpClient: httpClientMock, logger: log)

        tracker.trackMetric(token: "token", event: .delivered, deliveryId: "delivery-id", timestamp: nil) { _ in }

        XCTAssertEqual(httpClientMock.requestReceivedArguments?.params.url.absoluteString, "https://cdp.customer.io/v1/track")
    }

    func test_trackMetric_givenEuRegionAndNoApiHost_expectRequestToEuHost() {
        setUp(moduleConfig: .withApiHost(nil, region: .EU))
        let tracker = RichPushDeliveryTrackerImpl(httpClient: httpClientMock, logger: log)

        tracker.trackMetric(token: "token", event: .delivered, deliveryId: "delivery-id", timestamp: nil) { _ in }

        XCTAssertEqual(httpClientMock.requestReceivedArguments?.params.url.absoluteString, "https://cdp-eu.customer.io/v1/track")
    }

    func test_trackMetric_givenCustomApiHost_expectRequestToCustomHost() {
        setUp(moduleConfig: .withApiHost("proxy.example.com/v1", region: .EU))
        let tracker = RichPushDeliveryTrackerImpl(httpClient: httpClientMock, logger: log)

        tracker.trackMetric(token: "token", event: .delivered, deliveryId: "delivery-id", timestamp: nil) { _ in }

        XCTAssertEqual(httpClientMock.requestReceivedArguments?.params.url.absoluteString, "https://proxy.example.com/v1/track")
    }

    func test_trackMetric_givenInvalidApiHost_expectNoRequestMade() {
        setUp(moduleConfig: .withApiHost("proxy example.com/v1"))
        let tracker = RichPushDeliveryTrackerImpl(httpClient: httpClientMock, logger: log)
        var actualResult: Result<Void, HttpRequestError>?

        tracker.trackMetric(token: "token", event: .delivered, deliveryId: "delivery-id", timestamp: nil) { actualResult = $0 }

        XCTAssertFalse(httpClientMock.requestCalled)
        guard case .failure(.noRequestMade) = actualResult else {
            return XCTFail("expected noRequestMade, got \(String(describing: actualResult))")
        }
    }
}
