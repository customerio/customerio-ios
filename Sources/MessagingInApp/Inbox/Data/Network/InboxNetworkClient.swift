import CioInternalCommon
import Foundation

/// Result of an inbox data fetch: the raw body plus the HTTP response (for header/status reads).
typealias InboxNetworkResponse = (data: Data, response: HTTPURLResponse)

/// Thin async HTTP client for the visual-inbox data-layer GET endpoints
/// (`/api/v1/templates`, `/api/v1/branding`).
///
/// Routes through the existing gist network stack (`GistQueueNetwork`), so it reuses the same
/// session, consumer host, and auth headers (site id, encoded user token, anonymous flag,
/// datacenter, client version/platform). The endpoints declare a per-attempt 5s timeout via
/// `InboxEndpoint.timeoutInterval`, applied by `GistQueueNetworkImpl`; the queue client keeps the
/// URLSession default timeout.
///
/// Note: not `AutoMockable` — the async requirement isn't expressible by the mock template,
/// so tests use a hand-rolled stub (`InboxNetworkClientStub`).
protocol InboxNetworkClient: Sendable {
    /// Performs a GET request for the given endpoint.
    /// - Throws: `InboxNetworkError` on transport/HTTP failure or a missing user identifier.
    func get(endpoint: InboxEndpoint, state: InAppMessageState) async throws -> InboxNetworkResponse
}

enum InboxNetworkError: Error, Equatable {
    case invalidBaseURL
    case missingUserIdentifier
    case transport(String)
    case httpStatus(Int)
    case noResponse
}

// sourcery: InjectRegisterShared = "InboxNetworkClient"
final class InboxNetworkClientImpl: InboxNetworkClient, @unchecked Sendable {
    /// Per-attempt request timeout for inbox fetches. Applies to this path only.
    static let requestTimeout: TimeInterval = 5

    private let gistQueueNetwork: GistQueueNetwork

    init(gistQueueNetwork: GistQueueNetwork) {
        self.gistQueueNetwork = gistQueueNetwork
    }

    func get(endpoint: InboxEndpoint, state: InAppMessageState) async throws -> InboxNetworkResponse {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try gistQueueNetwork.request(state: state, request: endpoint) { result in
                    switch result {
                    case .success(let (data, response)):
                        continuation.resume(returning: (data, response))
                    case .failure(let error):
                        continuation.resume(throwing: InboxNetworkError.transport(error.localizedDescription))
                    }
                }
            } catch let error as GistNetworkRequestError {
                switch error {
                case .invalidBaseURL:
                    continuation.resume(throwing: InboxNetworkError.invalidBaseURL)
                case .missingUserIdentifier:
                    continuation.resume(throwing: InboxNetworkError.missingUserIdentifier)
                }
            } catch {
                continuation.resume(throwing: InboxNetworkError.transport(error.localizedDescription))
            }
        }
    }
}
