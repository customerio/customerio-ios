@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

/// URLProtocol stub that immediately fails every request with a configurable transport error.
/// Registered with the global URL loading system (URLSession.shared) in BaseNetworkTest setUp/tearDown.
private final class TransportErrorURLProtocol: URLProtocol {
    static var stub: Error = URLError(.timedOut)

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: Self.stub)
    }

    override func stopLoading() {}
}

class BaseNetworkTest: UnitTest {
    private let baseURL = URL(string: "https://gist-sdk.customer.io")!

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(TransportErrorURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(TransportErrorURLProtocol.self)
        super.tearDown()
    }

    // MARK: - Double-completion guard (MBL-2321)

    // Before the fix, a transport error (error != nil, data == nil) caused
    // completionHandler to fire twice: once from the `if let error` branch
    // (which lacked a `return`) and again from the `guard` fallthrough.
    // On the visual-inbox path the handler is wrapped in a Swift checked
    // continuation; a second resume is a SWIFT TASK CONTINUATION MISUSE
    // fatal crash -- 39 crashes / 28 users in 17 days on App Store builds.
    func test_request_givenTransportError_expectCompletionCalledExactlyOnce() throws {
        TransportErrorURLProtocol.stub = URLError(.timedOut)

        let completion = expectation(description: "completion called")
        completion.assertForOverFulfill = true

        var completionCount = 0
        let urlRequest = URLRequest(url: baseURL.appendingPathComponent(QueueEndpoint.getUserQueue.path))

        try BaseNetwork.request(
            QueueEndpoint.getUserQueue,
            urlRequest: urlRequest,
            baseURL: baseURL
        ) { _ in
            completionCount += 1
            completion.fulfill()
        }

        waitForExpectations(timeout: 3.0)
        XCTAssertEqual(completionCount, 1, "completionHandler must fire exactly once on transport error")
    }

    func test_request_givenDnsError_expectCompletionCalledExactlyOnce() throws {
        TransportErrorURLProtocol.stub = URLError(.cannotFindHost)

        let completion = expectation(description: "completion called")
        completion.assertForOverFulfill = true

        var completionCount = 0
        let urlRequest = URLRequest(url: baseURL.appendingPathComponent(QueueEndpoint.getUserQueue.path))

        try BaseNetwork.request(
            QueueEndpoint.getUserQueue,
            urlRequest: urlRequest,
            baseURL: baseURL
        ) { _ in
            completionCount += 1
            completion.fulfill()
        }

        waitForExpectations(timeout: 3.0)
        XCTAssertEqual(completionCount, 1, "completionHandler must fire exactly once on DNS error")
    }

    func test_request_givenTransportError_expectCompletionReceivesTransportError() throws {
        let givenError = URLError(.notConnectedToInternet)
        TransportErrorURLProtocol.stub = givenError

        let completion = expectation(description: "completion called")

        var receivedResult: Result<GistNetworkResponse, Error>?
        let urlRequest = URLRequest(url: baseURL.appendingPathComponent(QueueEndpoint.getUserQueue.path))

        try BaseNetwork.request(
            QueueEndpoint.getUserQueue,
            urlRequest: urlRequest,
            baseURL: baseURL
        ) { result in
            receivedResult = result
            completion.fulfill()
        }

        waitForExpectations(timeout: 3.0)
        guard case .failure(let error) = receivedResult else {
            return XCTFail("expected failure, got success")
        }
        XCTAssertEqual((error as? URLError)?.code, givenError.code)
    }
}
