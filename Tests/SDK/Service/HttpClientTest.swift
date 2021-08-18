@testable import CIO
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

class HttpClientTest: UnitTest {
    private var requestRunnerMock: HttpRequestRunnerMock!
    private var client: HttpClient!

    private let url = URL(string: "https://customer.io")!

    override func setUp() {
        super.setUp()

        requestRunnerMock = HttpRequestRunnerMock()
        client = CIOHttpClient(httpRequestRunner: requestRunnerMock, region: Region.US)

        requestRunnerMock.getUrlEndpointRegionReturnValue = url
    }

    // MARK: request

    func test_request_givenCannotCreateUrl_expectReceiveError_expectRequestNotMade() {
        requestRunnerMock.getUrlEndpointRegionReturnValue = nil

        let expectComplete = expectation(description: "Expect to complete")
        client.request(.identifyCustomer(identifier: ""), headers: nil, body: nil) { result in
            XCTAssertFalse(self.requestRunnerMock.requestCalled)
            XCTAssertNotNil(result.error)

            guard case .urlConstruction = result.error! else {
                XCTFail()
                return
            }

            expectComplete.fulfill()
        }

        waitForExpectations()
    }

    func test_request_givenErrorDuringRequest_expectError() {
        let givenError = URLError(.notConnectedToInternet)
        let expected = HttpRequestError.underlyingError(givenError)

        requestRunnerMock.requestClosure = { _, onComplete in
            onComplete(nil, nil, givenError)
        }

        let expectComplete = expectation(description: "Expect to complete")
        client.request(.identifyCustomer(identifier: ""), headers: nil, body: nil) { result in
            XCTAssertTrue(self.requestRunnerMock.requestCalled)
            XCTAssertNotNil(result.error)

            guard case .underlyingError(let actual) = result.error! else {
                XCTFail()
                return
            }

            XCTAssertEqual(expected.description, actual.localizedDescription)

            expectComplete.fulfill()
        }

        waitForExpectations()
    }

    func test_request_givenNoResponse_expectError() {
        requestRunnerMock.requestClosure = { _, onComplete in
            onComplete(Data(), nil, nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        client.request(.identifyCustomer(identifier: ""), headers: nil, body: nil) { result in
            XCTAssertTrue(self.requestRunnerMock.requestCalled)
            XCTAssertNotNil(result.error)

            guard case .noResponse = result.error! else {
                XCTFail()
                return
            }

            expectComplete.fulfill()
        }

        waitForExpectations()
    }

    func test_request_givenNoData_expectError() {
        requestRunnerMock.requestClosure = { _, onComplete in
            onComplete(nil, HTTPURLResponse(url: self.url, statusCode: 200, httpVersion: nil, headerFields: nil), nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        client.request(.identifyCustomer(identifier: ""), headers: nil, body: nil) { result in
            XCTAssertTrue(self.requestRunnerMock.requestCalled)
            XCTAssertNotNil(result.error)

            guard case .noResponse = result.error! else {
                XCTFail()
                return
            }

            expectComplete.fulfill()
        }

        waitForExpectations()
    }

    func test_request_given401_expectError() {
        requestRunnerMock.requestClosure = { _, onComplete in
            onComplete(nil, HTTPURLResponse(url: self.url, statusCode: 401, httpVersion: nil, headerFields: nil), nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        client.request(.identifyCustomer(identifier: ""), headers: nil, body: nil) { result in
            XCTAssertTrue(self.requestRunnerMock.requestCalled)
            XCTAssertNotNil(result.error)

            guard case .unauthorized = result.error! else {
                XCTFail()
                return
            }

            expectComplete.fulfill()
        }

        waitForExpectations()
    }

    func test_request_givenUnsuccessfulStatusCode_expectError() {
        let expectedCode = 500
        let expectedError = HttpRequestError.unsuccessfulStatusCode(expectedCode)

        requestRunnerMock.requestClosure = { _, onComplete in
            onComplete(nil,
                       HTTPURLResponse(url: self.url, statusCode: expectedCode, httpVersion: nil, headerFields: nil),
                       nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        client.request(.identifyCustomer(identifier: ""), headers: nil, body: nil) { result in
            XCTAssertTrue(self.requestRunnerMock.requestCalled)
            XCTAssertNotNil(result.error)

            guard case .unsuccessfulStatusCode(let actualCode) = result.error!, let actualError = result.error else {
                XCTFail()
                return
            }

            XCTAssertEqual(actualCode, expectedCode)
            XCTAssertEqual(actualError.description, expectedError.description)

            expectComplete.fulfill()
        }

        waitForExpectations()
    }

    func test_request_givenSuccessfulResponse_expectGetResponseBody() {
        let expected = #"{ "message": "Success!" }"#.data!

        requestRunnerMock.requestClosure = { _, onComplete in
            onComplete(expected, HTTPURLResponse(url: self.url, statusCode: 200, httpVersion: nil, headerFields: nil),
                       nil)
        }

        let expectComplete = expectation(description: "Expect to complete")
        client.request(.identifyCustomer(identifier: ""), headers: nil, body: nil) { result in
            XCTAssertTrue(self.requestRunnerMock.requestCalled)
            XCTAssertNil(result.error)

            XCTAssertEqual(result.success, expected)

            expectComplete.fulfill()
        }

        waitForExpectations()
    }

    // MARK: getBasicAuthHeaderString

    func test_getBasicAuthHeaderString_givenHardCodedCredentials_expectCorrectString() {
        let givenSiteId = "oofjwo88283899c9jend"
        let givenApiKey = "0929d8c8elehnmfodofo"

        let expected = "b29mandvODgyODM4OTljOWplbmQ6MDkyOWQ4YzhlbGVobm1mb2RvZm8="
        let actual = CIOHttpClient.getBasicAuthHeaderString(siteId: givenSiteId, apiKey: givenApiKey)

        XCTAssertEqual(actual, expected)
    }
}
