@testable import Common
import Foundation
import SharedTests
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

class HttpClientTest: UnitTest {
    private var requestRunnerMock = HttpRequestRunnerMock()
    private var credentialsStoreMock = SdkCredentialsStoreMock()
    private var configStoreMock = SdkConfigStoreMock()
    private let globalDataStoreMock = GlobalDataStoreMock()
    private let timerMock = SimpleTimerMock()
    private let deviceInfoMock = DeviceInfoMock()

    private var client: HttpClient!

    private let url = URL(string: "https://customer.io")!

    override func setUp() {
        super.setUp()

        credentialsStoreMock.credentials = SdkCredentials(apiKey: String.random, region: Region.EU)
        deviceInfoMock.underlyingSdkVersion = "1.0.0" // HttpClient uses this during initialization. Needed to set now.

        configStoreMock.config = SdkConfig()

        client = CIOHttpClient(siteId: SiteId.random, sdkCredentialsStore: credentialsStoreMock,
                               configStore: configStoreMock, jsonAdapter: jsonAdapter,
                               httpRequestRunner: requestRunnerMock,
                               globalDataStore: globalDataStoreMock,
                               logger: log,
                               timer: timerMock,
                               retryPolicy: retryPolicyMock,
                               deviceInfo: deviceInfoMock)
    }

    private func assertHttpRequestsPaused(paused: Bool) {
        if paused {
            XCTAssertTrue(globalDataStoreMock.httpRequestsPauseEndsSetCalled)
        } else {
            XCTAssertFalse(globalDataStoreMock.httpRequestsPauseEndsSetCalled)
        }
    }

    // MARK: request

    func test_request_givenErrorDuringRequest_expectError() {
        let givenError = URLError(.notConnectedToInternet)

        requestRunnerMock.requestClosure = { _, _, _, onComplete in
            onComplete(nil, nil, givenError)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(endpoint: .identifyCustomer(identifier: ""), headers: nil, body: nil)
        client.request(params) { result in
            XCTAssertTrue(self.requestRunnerMock.requestCalled)
            guard case .noOrBadNetwork(let actualError) = result.error! else { return XCTFail() }
            guard case .notConnectedToInternet = actualError.code else { return XCTFail() }

            expectComplete.fulfill()
        }

        waitForExpectations()
    }

    func test_request_givenNoResponse_expectError() {
        requestRunnerMock.requestClosure = { _, _, _, onComplete in
            onComplete(Data(), nil, nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(endpoint: .identifyCustomer(identifier: ""), headers: nil, body: nil)
        client.request(params) { result in
            XCTAssertTrue(self.requestRunnerMock.requestCalled)
            guard case .noRequestMade = result.error! else { return XCTFail() }

            expectComplete.fulfill()
        }

        waitForExpectations()
    }

    func test_request_givenNoData_expectError() {
        requestRunnerMock.requestClosure = { _, _, _, onComplete in
            onComplete(nil, HTTPURLResponse(url: self.url, statusCode: 200, httpVersion: nil, headerFields: nil), nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(endpoint: .identifyCustomer(identifier: ""), headers: nil, body: nil)
        client.request(params) { result in
            XCTAssertTrue(self.requestRunnerMock.requestCalled)
            guard case .noRequestMade = result.error! else { return XCTFail() }

            expectComplete.fulfill()
        }

        waitForExpectations()
    }

    func test_request_givenSuccessfulResponse_expectGetResponseBody() {
        let expected = #"{ "message": "Success!" }"#.data!

        requestRunnerMock.requestClosure = { _, _, _, onComplete in
            onComplete(expected, HTTPURLResponse(url: self.url, statusCode: 200, httpVersion: nil, headerFields: nil),
                       nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(endpoint: .identifyCustomer(identifier: ""), headers: nil, body: nil)
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
        globalDataStoreMock.underlyingHttpRequestsPauseEnds = Date().addMinutes(10)

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(endpoint: .identifyCustomer(identifier: ""), headers: nil, body: nil)
        client.request(params) { result in
            guard case .noRequestMade = result.error! else { return XCTFail() }

            expectComplete.fulfill()
        }

        waitForExpectations()

        XCTAssertFalse(requestRunnerMock.requestCalled)
    }

    func test_request_givenHttpRequestsPauseExpired_expectMakeRequest() {
        globalDataStoreMock.underlyingHttpRequestsPauseEnds = Date().minusMinutes(10)

        requestRunnerMock.requestClosure = { _, _, _, onComplete in
            onComplete(Data(), HTTPURLResponse(url: self.url, statusCode: 200, httpVersion: nil, headerFields: nil),
                       nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(endpoint: .identifyCustomer(identifier: ""), headers: nil, body: nil)
        client.request(params) { _ in
            expectComplete.fulfill()
        }

        waitForExpectations()

        XCTAssertTrue(requestRunnerMock.requestCalled)
    }

    // MARK: test 401 status codes

    func test_request_given401_expectPauseRequests_expectReturnError() {
        requestRunnerMock.requestClosure = { _, _, _, onComplete in
            onComplete(nil, HTTPURLResponse(url: self.url, statusCode: 401, httpVersion: nil, headerFields: nil), nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(endpoint: .identifyCustomer(identifier: ""), headers: nil, body: nil)
        client.request(params) { result in
            XCTAssertTrue(self.requestRunnerMock.requestCalled)
            XCTAssertNotNil(result.error)

            guard case .unauthorized = result.error! else {
                XCTFail()
                return
            }

            expectComplete.fulfill()
        }

        waitForExpectations()

        assertHttpRequestsPaused(paused: true)
    }

    // MARK: test 4xx status codes

    func test_request_given4xx_expectPauseRequets_expectReturnError() {
        requestRunnerMock.requestClosure = { _, _, _, onComplete in
            onComplete(nil, HTTPURLResponse(url: self.url, statusCode: 403, httpVersion: nil, headerFields: nil), nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(endpoint: .identifyCustomer(identifier: ""), headers: nil, body: nil)
        client.request(params) { result in
            XCTAssertNotNil(result.error)

            expectComplete.fulfill()
        }

        waitForExpectations()

        assertHttpRequestsPaused(paused: false)
    }

    // MARK: test 500/5xx status codes

    func test_request_given500_expectRetryUntilSuccessful() {
        let successfulHttpRequestResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                            headerFields: nil)
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

        requestRunnerMock.requestClosure = { _, _, _, onComplete in
            onComplete(#"{"meta": { "error": "invalid id" }}"#.data,
                       httpRequestRunnerResponse,
                       nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(endpoint: .identifyCustomer(identifier: ""), headers: nil, body: nil)
        client.request(params) { result in
            guard case .success = result else { // expect get success after retrying.
                return XCTFail()
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

        requestRunnerMock.requestClosure = { _, _, _, onComplete in
            onComplete(#"{"meta": { "error": "invalid id" }}"#.data,
                       HTTPURLResponse(url: self.url, statusCode: 500, httpVersion: nil, headerFields: nil),
                       nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        let params = HttpRequestParams(endpoint: .identifyCustomer(identifier: ""), headers: nil, body: nil)
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

    // MARK: getUserAgent

    func test_getUserAgent_givenDeviceInfoNotAvailable_expectShortUserAgent() {
        let expected = "Customer.io iOS Client/1.0.1"
        deviceInfoMock.underlyingSdkVersion = "1.0.1"
        deviceInfoMock.underlyingDeviceModel = nil

        let actual = CIOHttpClient.getUserAgent(deviceInfo: deviceInfoMock)

        XCTAssertEqual(expected, actual)
    }

    func test_getUserAgent_givenDeviceInfoAvailable_expectLongUserAgent() {
        let expected = "Customer.io iOS Client/1.0.1 (iPhone12; iOS 14.1) io.customer.superawesomestore/3.4.5"
        deviceInfoMock.underlyingSdkVersion = "1.0.1"
        deviceInfoMock.underlyingDeviceModel = "iPhone12"
        deviceInfoMock.underlyingOsVersion = "14.1"
        deviceInfoMock.underlyingOsName = "iOS"
        deviceInfoMock.underlyingCustomerAppName = "SuperAwesomeStore"
        deviceInfoMock.underlyingCustomerBundleId = "io.customer.superawesomestore"
        deviceInfoMock.underlyingCustomerAppVersion = "3.4.5"

        let actual = CIOHttpClient.getUserAgent(deviceInfo: deviceInfoMock)

        XCTAssertEqual(expected, actual)
    }
}
