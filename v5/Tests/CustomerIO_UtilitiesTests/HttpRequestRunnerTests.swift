import Foundation
import Testing

@testable import CustomerIO_Utilities

@Suite(.serialized) struct HttpRequestRunnerTests {
    @MainActor
    @Test func performRequest_successful() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let runner = HttpRequestRunner(session: session)
        let url = URL(string: "https://example.com")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        await MainActor.run {
            MockURLProtocol.requestHandler.wrappedValue = { req in
                let data = "hello".data(using: .utf8)!
                let response = HTTPURLResponse(
                    url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (data, response)
            }
        }
        let (data, response) = try await runner.performRequest(request)
        #expect(String(data: data, encoding: .utf8) == "hello")
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    @MainActor
    @Test func performRequest_error() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let runner = HttpRequestRunner(session: session)
        let url = URL(string: "https://example.com")!
        let request = URLRequest(url: url)
        await MainActor.run {
            MockURLProtocol.requestHandler.wrappedValue = { _ in
                throw URLError(.timedOut)
            }
        }
        do {
            _ = try await runner.performRequest(request)
            #expect(false, "Expected error")
        } catch {
            #expect((error as? URLError)?.code == .timedOut)
        }
    }
}

// MARK: - MockURLProtocol

class MockURLProtocol: URLProtocol {
    static let requestHandler:
        Synchronized<(@Sendable (URLRequest) throws -> (Data, URLResponse))?> = Synchronized(nil)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let handler = MockURLProtocol.requestHandler.wrappedValue
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
