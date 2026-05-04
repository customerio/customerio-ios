import Foundation

/// URLSession-backed `HttpClient`. Uses a `withCheckedContinuation` wrapper
/// around the completion-handler API for iOS 13/14 compatibility.
public final class HttpRequestRunner: HttpClient, Sendable {

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        // Use completion-handler API for iOS 13/14 compatibility.
        // URLSession.data(for:) is only available on iOS 15+.
        return try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: (data, response))
            }.resume()
        }
    }
}
