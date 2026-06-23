@testable import CioMessagingInApp
import Foundation

/// Hand-rolled stub for the async `InboxNetworkClient`.
/// (The async requirement is not expressible by the AutoMockable template.)
final class InboxNetworkClientStub: InboxNetworkClient, @unchecked Sendable {
    /// Per-endpoint behavior. Returning a value succeeds; throwing fails that attempt.
    var handler: ((InboxEndpoint, InAppMessageState) throws -> InboxNetworkResponse)?

    /// Records every call (for asserting retry counts).
    private(set) var calls: [InboxEndpoint] = []
    private let lock = NSLock()

    func get(endpoint: InboxEndpoint, state: InAppMessageState) async throws -> InboxNetworkResponse {
        lock.lock()
        calls.append(endpoint)
        lock.unlock()

        guard let handler = handler else {
            throw InboxNetworkError.noResponse
        }
        return try handler(endpoint, state)
    }

    func callCount(for endpoint: InboxEndpoint) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return calls.filter { $0 == endpoint }.count
    }

    /// Builds an `InboxNetworkResponse` with the given JSON body and 200 status.
    static func response(json: String, status: Int = 200) -> InboxNetworkResponse {
        let data = Data(json.utf8)
        let response = HTTPURLResponse(
            url: URL(string: "https://consumer.inapp.customer.io")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

/// Network stub whose `get(...)` *suspends* (does not return) until `release()` is called.
///
/// Used to prove the repository's in-flight guard: while the first fetch is parked here, a second
/// concurrent `enableAndLoad()` must hit the guard and NOT issue its own network calls. The first
/// call also signals `waitUntilFirstCallStarted()` so the test can synchronize before releasing.
final class GatedInboxNetworkClientStub: InboxNetworkClient, @unchecked Sendable {
    private let templatesJSON: String
    private let brandingJSON: String

    private let lock = NSLock()
    private var calls: [InboxEndpoint] = []

    private let gate = DispatchSemaphore(value: 0)
    private let firstCallStarted = DispatchSemaphore(value: 0)
    private var firstCallSignaled = false

    init(templatesJSON: String, brandingJSON: String) {
        self.templatesJSON = templatesJSON
        self.brandingJSON = brandingJSON
    }

    func get(endpoint: InboxEndpoint, state: InAppMessageState) async throws -> InboxNetworkResponse {
        lock.lock()
        calls.append(endpoint)
        if !firstCallSignaled {
            firstCallSignaled = true
            firstCallStarted.signal()
        }
        lock.unlock()

        // Suspend (without blocking the actor) until the test releases the gate.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async { [gate] in
                gate.wait()
                continuation.resume()
            }
        }

        let json = endpoint == .getTemplates ? templatesJSON : brandingJSON
        return InboxNetworkClientStub.response(json: json)
    }

    /// Blocks until at least one `get(...)` call has begun.
    func waitUntilFirstCallStarted() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async { [firstCallStarted] in
                firstCallStarted.wait()
                continuation.resume()
            }
        }
    }

    /// Releases all parked calls (signals generously so both parallel endpoints proceed).
    func release() {
        for _ in 0 ..< 8 {
            gate.signal()
        }
    }

    func callCount(for endpoint: InboxEndpoint) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return calls.filter { $0 == endpoint }.count
    }
}
