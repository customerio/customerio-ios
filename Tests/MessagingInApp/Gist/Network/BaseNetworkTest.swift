@testable import CioMessagingInApp
import Foundation
import XCTest

// MARK: - URLProtocol stub that immediately fails every request with a transport error

/// Intercepts URLSession.shared requests and fails them with the given URLError.
/// This exercises the transport-error path in BaseNetwork without a real network hop.
final class FailingURLProtocol: URLProtocol {
    static var stubbedError: Error = URLError(.notConnectedToInternet)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: Self.stubbedError)
    }

    override func stopLoading() {}
}

// MARK: - BaseNetworkTest

/// Tests the completion-handler invocation count of BaseNetwork.request.
///
/// iOS cannot build on the Linux sandbox (MessagingInApp imports UIKit), so
/// these tests are authored here and verified by CI on macOS runners.
/// Local checks run: swiftformat --lint, swiftlint (if installed).
class BaseNetworkTest: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(FailingURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(FailingURLProtocol.self)
        super.tearDown()
    }

    // MARK: - Transport-error path: completion handler fires exactly once

    /// Regression test for MBL-2321.
    ///
    /// Before the fix, BaseNetwork called the completion handler twice on a
    /// transport error: once from the `if let error` branch and a second time
    /// from the `guard` that follows (because `data` is nil).  The second call
    /// crashed `withCheckedThrowingContinuation`-based callers with
    /// `SWIFT TASK CONTINUATION MISUSE`.
    ///
    /// `XCTestExpectation(assertForOverFulfill: true)` turns a double-call into
    /// an immediate test failure, giving us a deterministic red → green signal.
    func test_request_transportError_completionHandlerFiresExactlyOnce() throws {
        FailingURLProtocol.stubbedError = URLError(.timedOut)

        // expectedFulfillmentCount defaults to 1; assertForOverFulfill = true
        // makes a second fulfillment a hard test failure.
        let expectation = XCTestExpectation(description: "completion fires exactly once")
        expectation.assertForOverFulfill = true

        let baseURL = URL(string: "https://gist-sdk-test.example.com")!
        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "GET"

        try BaseNetwork.request(
            QueueEndpoint.getUserQueue,
            urlRequest: urlRequest,
            baseURL: baseURL,
            completionHandler: { result in
                if case .failure = result {
                    expectation.fulfill()
                }
            }
        )

        wait(for: [expectation], timeout: 3.0)
    }

    /// On a transport error the reported error should be the transport error
    /// itself, not `GistNetworkError.serverError` (which was the fallthrough
    /// value from the unfixed guard branch).
    func test_request_transportError_returnsTransportError() throws {
        let givenError = URLError(.notConnectedToInternet)
        FailingURLProtocol.stubbedError = givenError

        var capturedError: Error?
        let expectation = XCTestExpectation(description: "completion fires")
        expectation.assertForOverFulfill = true

        let baseURL = URL(string: "https://gist-sdk-test.example.com")!
        let urlRequest = URLRequest(url: baseURL)

        try BaseNetwork.request(
            QueueEndpoint.getUserQueue,
            urlRequest: urlRequest,
            baseURL: baseURL,
            completionHandler: { result in
                if case .failure(let error) = result {
                    capturedError = error
                }
                expectation.fulfill()
            }
        )

        wait(for: [expectation], timeout: 3.0)

        let urlError = try XCTUnwrap(capturedError as? URLError)
        XCTAssertEqual(urlError.code, .notConnectedToInternet)
    }
}
