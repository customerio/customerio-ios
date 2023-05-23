@testable import CioInternalCommon
import Foundation
import SharedTests
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

class HttpClientTest: UnitTest {
    private var requestRunnerMock = HttpRequestRunnerMock()
    private let globalDataStoreMock = GlobalDataStoreMock()
    private let timerMock = SimpleTimerMock()
    private let baseHttpUrls = HttpBaseUrls.getProduction(region: .US)
    private let userAgentUtilMock = UserAgentUtilMock()

    private var client: CIOHttpClient!

    private let url = URL(string: "https://customer.io")!

    override func setUp() {
        super.setUp()

        userAgentUtilMock
            .getUserAgentHeaderValueReturnValue =
            "user-agent-here" // HttpClient uses this during initialization. Needed to set now.

        client = CIOHttpClient(
            sdkConfig: sdkConfig,
            jsonAdapter: jsonAdapter,
            httpRequestRunner: requestRunnerMock,
            globalDataStore: globalDataStoreMock,
            logger: log,
            timer: timerMock,
            retryPolicy: retryPolicyMock,
            userAgentUtil: userAgentUtilMock
        )
    }

    // MARK: request

    func test_request_givenErrorDuringRequest_expectError() {
        let givenError = URLError(.notConnectedToInternet)

        mockRequestResponse {
            (body: nil, response: nil, failure: givenError)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(
            endpoint: .identifyCustomer(identifier: ""),
            baseUrls: baseHttpUrls,
            headers: nil,
            body: nil
        )!
        client.request(params) { result in
            XCTAssertTrue(self.requestRunnerMock.requestCalled)
            guard case .noOrBadNetwork(let actualError) = result.error!,
                  case .notConnectedToInternet = actualError.code
            else {
                return XCTFail("expect request failed because not connected to internet")
            }

            expectComplete.fulfill()
        }

        waitForExpectations()
    }

    func test_request_givenNoResponse_expectError() {
        mockRequestResponse {
            (body: "".data, response: nil, failure: nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(
            endpoint: .identifyCustomer(identifier: ""),
            baseUrls: baseHttpUrls,
            headers: nil,
            body: nil
        )!
        client.request(params) { result in
            XCTAssertTrue(self.requestRunnerMock.requestCalled)
            guard case .noRequestMade = result.error! else {
                return XCTFail("expect no request was made")
            }

            expectComplete.fulfill()
        }

        waitForExpectations()
    }

    func test_request_givenNoData_expectError() {
        mockRequestResponse {
            (body: nil, response: HTTPURLResponse(url: self.url, statusCode: 200, httpVersion: nil, headerFields: nil), failure: nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(
            endpoint: .identifyCustomer(identifier: ""),
            baseUrls: baseHttpUrls,
            headers: nil,
            body: nil
        )!
        client.request(params) { result in
            XCTAssertTrue(self.requestRunnerMock.requestCalled)
            guard case .noRequestMade = result.error! else {
                return XCTFail("expect no request was made")
            }

            expectComplete.fulfill()
        }

        waitForExpectations()
    }

    func test_request_givenSuccessfulResponse_expectGetResponseBody() {
        let expected = #"{ "message": "Success!" }"#.data!

        mockRequestResponse {
            (body: expected, response: HTTPURLResponse(url: self.url, statusCode: 200, httpVersion: nil, headerFields: nil), failure: nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(
            endpoint: .identifyCustomer(identifier: ""),
            baseUrls: baseHttpUrls,
            headers: nil,
            body: nil
        )!
        client.request(params) { result in
            XCTAssertTrue(self.requestRunnerMock.requestCalled)
            XCTAssertNil(result.error)

            XCTAssertEqual(result.success, expected)

            expectComplete.fulfill()
        }

        waitForExpectations()

        assertHttpRequestsPaused(paused: false)
    }

    func test_request_givenHttpRequestsPaused_expectDontMakeRequest() {
        globalDataStoreMock.underlyingHttpRequestsPauseEnds = Date().add(10, .minute)

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(
            endpoint: .identifyCustomer(identifier: ""),
            baseUrls: baseHttpUrls,
            headers: nil,
            body: nil
        )!
        client.request(params) { result in
            guard case .noRequestMade = result.error! else {
                return XCTFail("expect no request was made")
            }

            expectComplete.fulfill()
        }

        waitForExpectations()

        XCTAssertFalse(requestRunnerMock.requestCalled)
    }

    func test_request_givenHttpRequestsPauseExpired_expectMakeRequest() {
        globalDataStoreMock.underlyingHttpRequestsPauseEnds = Date().subtract(10, .minute)

        mockRequestResponse {
            (body: "".data, response: HTTPURLResponse(url: self.url, statusCode: 200, httpVersion: nil, headerFields: nil), failure: nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(
            endpoint: .identifyCustomer(identifier: ""),
            baseUrls: baseHttpUrls,
            headers: nil,
            body: nil
        )!
        client.request(params) { _ in
            expectComplete.fulfill()
        }

        waitForExpectations()

        XCTAssertTrue(requestRunnerMock.requestCalled)
    }

    // MARK: test 401 status codes

    func test_request_given401_expectPauseRequests_expectReturnError() {
        mockRequestResponse {
            (body: nil, response: HTTPURLResponse(url: self.url, statusCode: 401, httpVersion: nil, headerFields: nil), failure: nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(
            endpoint: .identifyCustomer(identifier: ""),
            baseUrls: baseHttpUrls,
            headers: nil,
            body: nil
        )!
        client.request(params) { result in
            XCTAssertTrue(self.requestRunnerMock.requestCalled)
            XCTAssertNotNil(result.error)

            guard case .unauthorized = result.error! else {
                return XCTFail("expected request to not have been authorized")
            }

            expectComplete.fulfill()
        }

        waitForExpectations()

        assertHttpRequestsPaused(paused: true)
    }

    // MARK: test 4xx status codes

    func test_request_given4xx_expectPauseRequets_expectReturnError() {
        mockRequestResponse {
            (body: nil, response: HTTPURLResponse(url: self.url, statusCode: 403, httpVersion: nil, headerFields: nil), failure: nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(
            endpoint: .identifyCustomer(identifier: ""),
            baseUrls: baseHttpUrls,
            headers: nil,
            body: nil
        )!
        client.request(params) { result in
            XCTAssertNotNil(result.error)

            expectComplete.fulfill()
        }

        waitForExpectations()

        assertHttpRequestsPaused(paused: false)
    }

    // MARK: test 400 status codes

    func test_request_given400_expectPauseRequestsFalse_expectReturn400ErrorClass() {
        mockRequestResponse {
            (body: nil, response: HTTPURLResponse(url: self.url, statusCode: 400, httpVersion: nil, headerFields: nil), failure: nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(
            endpoint: .identifyCustomer(identifier: ""),
            baseUrls: baseHttpUrls,
            headers: nil,
            body: nil
        )!
        client.request(params) { result in
            XCTAssertNotNil(result.error)
            guard case .badRequest400 = result.error else {
                return XCTFail("expected 400 responses have it's own enum case returned")
            }

            expectComplete.fulfill()
        }

        waitForExpectations()

        assertHttpRequestsPaused(paused: false)
    }

    // MARK: test 500/5xx status codes

    func test_request_given500_expectRetryUntilSuccessful() {
        let successfulHttpRequestResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        let failedHttpRequestResponse = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)
        var httpRequestRunnerResponse = failedHttpRequestResponse

        var numberOfTimesToRetry = 3
        timerMock.scheduleAndCancelPreviousClosure = { _, onComplete in
            if numberOfTimesToRetry == 0 {
                httpRequestRunnerResponse = successfulHttpRequestResponse
            }

            numberOfTimesToRetry -= 1

            onComplete()
        }

        mockRequestResponse {
            (body: #"{"meta": { "error": "invalid id" }}"#.data, response: httpRequestRunnerResponse, failure: nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(
            endpoint: .identifyCustomer(identifier: ""),
            baseUrls: baseHttpUrls,
            headers: nil,
            body: nil
        )!
        client.request(params) { result in
            guard case .success = result else { // expect get success after retrying.
                return XCTFail("expect get success after retrying")
            }

            expectComplete.fulfill()
        }

        waitForExpectations()

        assertHttpRequestsPaused(paused: false)
        XCTAssertGreaterThan(requestRunnerMock.requestCallsCount, 3)
    }

    func test_request_given500_expectPauseAndReturnErrorAfterRetrying() {
        var numberOfTimesToRetry = 3
        timerMock.scheduleAndCancelPreviousClosure = { _, onComplete in
            if numberOfTimesToRetry == 0 {
                self.retryPolicyMock.underlyingNextSleepTime = nil
            }

            numberOfTimesToRetry -= 1

            onComplete()
        }

        mockRequestResponse {
            (body: #"{"meta": { "error": "invalid id" }}"#.data, response: HTTPURLResponse(url: self.url, statusCode: 500, httpVersion: nil, headerFields: nil), failure: nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(
            endpoint: .identifyCustomer(identifier: ""),
            baseUrls: baseHttpUrls,
            headers: nil,
            body: nil
        )!
        client.request(params) { result in
            XCTAssertNotNil(result.error)

            expectComplete.fulfill()
        }

        waitForExpectations()

        assertHttpRequestsPaused(paused: true)
        XCTAssertGreaterThan(requestRunnerMock.requestCallsCount, 3)
    }

    // MARK: getBasicAuthHeaderString

    func test_getBasicAuthHeaderString_givenHardCodedCredentials_expectCorrectString() {
        let givenSiteId = "oofjwo88283899c9jend"
        let givenApiKey = "0929d8c8elehnmfodofo"

        let expected = "b29mandvODgyODM4OTljOWplbmQ6MDkyOWQ4YzhlbGVobm1mb2RvZm8="
        let actual = CIOHttpClient.getBasicAuthHeaderString(siteId: givenSiteId, apiKey: givenApiKey)

        XCTAssertEqual(actual, expected)
    }

    // MARK: getSessionForRequest

    func test_getSessionForRequest_givenCIOApiEndpoint_expectGetCIOApiSession() {
        let cioApiEndpointUrl = HttpRequestParams(
            endpoint: .trackDeliveryMetrics,
            baseUrls: baseHttpUrls,
            headers: nil,
            body: nil
        )!.url

        let actualSession = client.getSessionForRequest(url: cioApiEndpointUrl)

        let containsAuthorizationHeader = actualSession.configuration.httpAdditionalHeaders!["Authorization"] != nil
        XCTAssertTrue(containsAuthorizationHeader)
    }

    func test_getSessionForRequest_givenCIOAssetLibraryEndpoint_expectPublicSession() {
        let actualSession = client.getSessionForRequest(url: URL(string: "https://storage.googleapis.com/cio-asset-manager-standalone/1670599791846_frederick_adoption_day.jpg")!)

        let containsAuthorizationHeader = actualSession.configuration.httpAdditionalHeaders!["Authorization"] != nil
        XCTAssertFalse(containsAuthorizationHeader)
    }
}

extension HttpClientTest {
    private func assertHttpRequestsPaused(paused: Bool) {
        if paused {
            XCTAssertTrue(globalDataStoreMock.httpRequestsPauseEndsSetCalled)
        } else {
            XCTAssertFalse(globalDataStoreMock.httpRequestsPauseEndsSetCalled)
        }
    }

    // OK with a large tuple since this is just setting up a test. No need to make a custom data type just to setup test functions.
    // swiftlint:disable:next large_tuple
    private func mockRequestResponse(onComplete: @escaping () -> (body: Data?, response: HTTPURLResponse?, failure: Error?)) {
        requestRunnerMock.requestClosure = { _, _, actualOnComplete in
            let result = onComplete()
            actualOnComplete(result.body, result.response, result.failure)
        }
    }
}
