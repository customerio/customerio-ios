@testable import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class MessagingPushImplementationTest: UnitTest {
    private var mockCustomerIO = CustomerIOInstanceMock()
    private var messagingPush: MessagingPushImplementation!

    private var eventBusMock = EventBusMock()
    private var httpClientMock = HttpClientMock()
    private let pushDeviceTokenRepositoryMock = PushDeviceTokenRepositoryMock()

    override func setUp() {
        super.setUp()

        mockCustomerIO.siteId = testSiteId

        messagingPush = MessagingPushImplementation(httpClient: httpClientMock, jsonAdapter: jsonAdapter,
                                                    eventBus: eventBusMock,
                                                    pushDeviceTokenRepository: pushDeviceTokenRepositoryMock)
    }

    // MARK: trackMetric

    func test_trackMetric_givenHttpSuccess_expectSuccess() {
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }

        let expect = expectation(description: "Expect trackMetric to succeed")
        messagingPush.trackMetric(deliveryID: String.random, event: .delivered, deviceToken: String.random) { result in
            guard case .success = result else { return XCTFail() }
            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertTrue(httpClientMock.requestCalled)
    }

    func test_trackMetric_givenHttpFailure_expectFailure() {
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.failure(HttpRequestError.unsuccessfulStatusCode(500, apiMessage: "")))
        }

        let expect = expectation(description: "Expect trackMetric to fail")
        messagingPush.trackMetric(deliveryID: String.random, event: .delivered, deviceToken: String.random) { result in
            guard case .failure(let actualError) = result else { return XCTFail() }
            guard case .http(let httpError) = actualError else { return XCTFail() }
            guard case .unsuccessfulStatusCode(let code, _) = httpError, code == 500 else { return XCTFail() }
            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertTrue(httpClientMock.requestCalled)
    }
}
