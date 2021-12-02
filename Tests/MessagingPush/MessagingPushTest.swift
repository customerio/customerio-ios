@testable import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class MessagingPushTest: UnitTest {
    private var mockCustomerIO = CustomerIOInstanceMock()
    private var messagingPush: MessagingPush!

    override func setUp() {
        super.setUp()

        messagingPush = MessagingPush(customerIO: mockCustomerIO)
    }

    // MARK: trackMetric

    func test_trackMetric_givenHttpSuccess_expectSuccess() {
        let expect = expectation(description: "Expect to complete")
        messagingPush.trackMetric(deliveryID: String.random, event: .delivered, deviceToken: String.random) { result in
            guard case .failure(let error) = result else { return XCTFail() }
            guard case .notInitialized = error else { return XCTFail() }
            expect.fulfill()
        }

        waitForExpectations()
    }

    // MARK: deinit

    func test_givenNilObject_expectDeinit() {
        let cio = CustomerIO(siteId: String.random, apiKey: String.random)

        var messagingPush: MessagingPush? = MessagingPush(customerIO: cio)

        messagingPush = nil

        XCTAssertNil(messagingPush)
    }
}
