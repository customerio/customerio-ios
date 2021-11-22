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

    // MARK: registerDeviceToken

    func test_registerDeviceToken_givenSdkNotInitialized_expectFail() {
        let expect = expectation(description: "Expect to fail to register device token")
        messagingPush.registerDeviceToken(String.random) { result in
            guard case .failure(let error) = result else { return XCTFail() }
            guard case .notInitialized = error else { return XCTFail() }
            expect.fulfill()
        }

        waitForExpectations()
    }

    // MARK: deleteDeviceToken

    func test_deleteDeviceToken_expectSuccessIfNoToken() {
        let expect = expectation(description: "Expect to complete")
        messagingPush.deleteDeviceToken { result in
            guard case .failure(let error) = result else { return XCTFail() }
            guard case .notInitialized = error else { return XCTFail() }
            expect.fulfill()
        }

        waitForExpectations()
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
