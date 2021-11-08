@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class IdentifyRepositoryTest: UnitTest {
    private var httpClientMock = HttpClientMock()
    private var siteId: String!

    private var repository: IdentifyRepository!
    private var integrationRepository: IdentifyRepository!

    override func setUp() {
        super.setUp()

        siteId = String.random

        repository = CIOIdentifyRepository(siteId: siteId, httpClient: httpClientMock, jsonAdapter: jsonAdapter)
        integrationRepository = CIOIdentifyRepository(siteId: siteId,
                                                      httpClient: httpClientMock,
                                                      jsonAdapter: jsonAdapter)
    }

    // MARK: addOrUpdateCustomer

    func test_addOrUpdateCustomer_expectCallHttpClientWithCorrectParams() {
        let givenIdentifier = String.random
        let givenBody = jsonAdapter.toJsonString(IdentifyRequestBody.random())!

        httpClientMock.requestClosure = { params, onComplete in
            guard case .identifyCustomer(let actualIdentifier) = params.endpoint else { return XCTFail() }
            XCTAssertEqual(actualIdentifier, givenIdentifier)
            XCTAssertEqual(givenBody.data, params.body)

            onComplete(Result.success(params.body!))
        }

        let expect = expectation(description: "Expect to complete")
        repository.addOrUpdateCustomer(identifier: givenIdentifier, requestBodyString: givenBody) { _ in
            expect.fulfill()
        }

        waitForExpectations()
    }

    func test_addOrUpdateCustomer_givenHttpFailure_expectGetError() {
        let givenIdentifier = String.random
        let givenBody = IdentifyRequestBody.random()

        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.failure(HttpRequestError.unsuccessfulStatusCode(500, apiMessage: "")))
        }

        let expect = expectation(description: "Expect to complete")
        repository.addOrUpdateCustomer(identifier: givenIdentifier,
                                       requestBodyString: jsonAdapter.toJsonString(givenBody)) { result in
            guard case .failure(let actualError) = result else { return XCTFail() }
            guard case .http(let httpError) = actualError else { return XCTFail() }
            guard case .unsuccessfulStatusCode(let code, _) = httpError, code == 500 else { return XCTFail() }
            expect.fulfill()
        }

        waitForExpectations()
    }

    // MARK: trackEvent

    func test_trackEvent_expectCallHttpClientWithCorrectParams() {
        let givenEventName = String.random
        let givenEventData = TrackEventData.random()
        let givenTimestamp = Date(timeIntervalSince1970: 1631731924)
        let givenIdentifier = String.random
        let givenBody = jsonAdapter
            .toJsonString(TrackRequestBody(name: givenEventName, data: givenEventData, timestamp: givenTimestamp))!

        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }

        let expect = expectation(description: "Expect to complete")
        httpClientMock.requestClosure = { params, onComplete in
            guard case .trackCustomerEvent(let actualIdentifier) = params.endpoint else { return XCTFail() }
            XCTAssertEqual(actualIdentifier, givenIdentifier)
            XCTAssertEqual(givenBody.data, params.body)

            onComplete(Result.success(params.body!))
        }
        repository.trackEvent(profileIdentifier: givenIdentifier, requestBodyString: givenBody) { _ in
            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertEqual(httpClientMock.requestCallsCount, 1)
    }

    func test_trackEvent_givenHttpFailure_expectGetError() {
        let givenIdentifier = String.random
        let givenBody = jsonAdapter
            .toJsonString(TrackRequestBody<String>(name: String.random, data: nil, timestamp: Date()))!

        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.failure(HttpRequestError.unsuccessfulStatusCode(500, apiMessage: "")))
        }

        let expect = expectation(description: "Expect to complete")
        repository.trackEvent(profileIdentifier: givenIdentifier, requestBodyString: givenBody) { result in
            guard case .failure(let actualError) = result else { return XCTFail() }
            guard case .http(let httpError) = actualError else { return XCTFail() }
            guard case .unsuccessfulStatusCode(let code, _) = httpError, code == 500 else { return XCTFail() }

            expect.fulfill()
        }

        waitForExpectations()
    }
}
