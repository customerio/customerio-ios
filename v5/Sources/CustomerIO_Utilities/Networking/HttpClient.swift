import Foundation

/// Minimal HTTP client protocol. Inject a mock in tests; register the
/// URLSession-backed implementation via the DI container in production.
public protocol HttpClient: Sendable {
    func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse)
}
