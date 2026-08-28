@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

// MARK: - URLProtocol stub

/// Intercepts every URLSession.shared request and immediately fails it with the configured
/// URLError, simulating a transport-level failure (timeout / dropped connection / DNS).
/// Used to verify that BaseNetwork.request does not call its completion handler more than once.
private final class TransportErrorURLProtocol: URLProtocol {
    static var simulatedError = URLError(.timedOut)

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: TransportErrorURLProtocol.simulatedError)
    }

    override func stopLoading() {}
}

// MARK: - Tests

/// Tests for `BaseNetwork.request` transport-error handling.
///
/// These tests exercise the URLSession.shared dataTask path via a registered URLProtocol
/// stub so no real network calls are made. `swift test` must run on macOS CI (the Linux
/// sandbox cannot build MessagingInApp because it imports UIKit); the test logic itself is
/// platform-independent.
class BaseNetworkTest: UnitTest {
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(TransportErrorURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(TransportErrorURLProtocol.self)
        super.tearDown()
    }

    // MARK: - MBL-2321: single completion on transport error

    /// On a transport-level failure (URLSession delivers a non-nil error AND nil data),
    /// `BaseNetwork.request` must call its completion handler exactly once.
    ///
    /// Prior to the fix the `if let error` branch called the handler but did NOT return,
    /// so the guard-else branch fired a second time with `GistNetworkError.serverError`.
    /// `XCTestExpectation.assertForOverFulfill = true` turns a second fulfill() into a
    /// test failure, making over-invocation impossible to miss.
    func test_request_onTransportError_completionHandlerFiresExactlyOnce() throws {
        let baseURL = URL(string: "https://test.gist-sdk.io")!
        let urlRequest = URLRequest(url: baseURL)

        let callCountExpectation = expectation(description: "Completion handler called exactly once")
        callCountExpectation.assertForOverFulfill = true

        var callCount = 0

        try BaseNetwork.request(
            QueueEndpoint.getUserQueue,
            urlRequest: urlRequest,
            baseURL: baseURL
        ) { _ in
            callCount += 1
            callCountExpectation.fulfill()
        }

        wait(for: [callCountExpectation], timeout: 2.0)
        XCTAssertEqual(callCount, 1, "Completion handler must fire exactly once on transport error")
    }

    /// The result delivered on a transport error must be `.failure` wrapping the original
    /// URLError, not the synthetic `GistNetworkError.serverError` that the guard-else
    /// branch would have produced.
    func test_request_onTransportError_deliversOriginalURLError() throws {
        let baseURL = URL(string: "https://test.gist-sdk.io")!
        let urlRequest = URLRequest(url: baseURL)
        let expectedCode = URLError.Code.timedOut
        TransportErrorURLProtocol.simulatedError = URLError(expectedCode)

        let done = expectation(description: "Completion handler called")

        try BaseNetwork.request(
            QueueEndpoint.getUserQueue,
            urlRequest: urlRequest,
            baseURL: baseURL
        ) { result in
            if case .failure(let error) = result, let urlError = error as? URLError {
                XCTAssertEqual(urlError.code, expectedCode)
            } else {
                XCTFail("Expected .failure(URLError(.timedOut)), got \(result)")
            }
            done.fulfill()
        }

        wait(for: [done], timeout: 2.0)
    }
}
