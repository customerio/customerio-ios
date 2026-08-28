@testable import CioMessagingInApp
@testable import CioMessagingInAppMocks
import Foundation
import SharedTests
import XCTest

/// Tests for `InboxNetworkClientImpl.get` -- specifically the belt-and-suspenders guard
/// that prevents a duplicate callback from resuming a `CheckedContinuation` twice.
///
/// `swift test` must run on macOS CI; the sandbox cannot build MessagingInApp on Linux.
class InboxNetworkClientTests: UnitTest {
    private var networkMock: GistQueueNetworkMock!
    private var client: InboxNetworkClientImpl!

    override func setUp() {
        super.setUp()
        networkMock = GistQueueNetworkMock()
        client = InboxNetworkClientImpl(gistQueueNetwork: networkMock)
    }

    // MARK: - Helpers

    private func makeState(userId: String = "test-user") -> InAppMessageState {
        InAppMessageState(userId: userId)
    }

    // MARK: - MBL-2321: duplicate callback must not crash

    /// A `GistQueueNetwork` that fires its completion handler TWICE simulates the exact
    /// crash scenario from MBL-2321: BaseNetwork calls the handler once for the URLError
    /// then falls through and calls it a second time with `GistNetworkError.serverError`.
    ///
    /// After hardening, the second call must be silently ignored -- not a fatal crash.
    func test_get_onDoubleFiringCallback_doesNotCrash() async throws {
        networkMock.requestClosure = { _, _, completionHandler in
            // First call: transport error (matches what BaseNetwork delivers on URLError)
            completionHandler(.failure(URLError(.timedOut)))
            // Second call: the bug -- GistNetworkError.serverError from the guard-else branch.
            // With the hasResumed guard in place this must be a no-op.
            completionHandler(.failure(GistNetworkError.serverError))
        }

        do {
            _ = try await client.get(endpoint: .getTemplates, state: makeState())
            XCTFail("Expected an error; first callback delivered a failure")
        } catch {
            // The first callback's error surfaced correctly.
            // If the second callback were not guarded, we would never reach this assertion --
            // the process would have already crashed with SWIFT TASK CONTINUATION MISUSE.
            let networkError = error as? InboxNetworkError
            XCTAssertNotNil(networkError, "Error should be InboxNetworkError, got \(error)")
        }
    }

    /// A second double-fire scenario where the first callback is a success: the guard
    /// must still block the trailing failure from resuming the continuation a second time.
    func test_get_onSuccessThenDoubleFire_doesNotCrash() async throws {
        let data = Data("{}".utf8)
        let response = HTTPURLResponse(
            url: URL(string: "https://consumer.inapp.customer.io/api/v1/templates")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        networkMock.requestClosure = { _, _, completionHandler in
            completionHandler(.success((data, response)))
            // Spurious second call -- must be ignored.
            completionHandler(.failure(GistNetworkError.serverError))
        }

        let result = try await client.get(endpoint: .getTemplates, state: makeState())
        XCTAssertEqual(result.data, data)
    }

    // MARK: - Normal success path (regression guard)

    func test_get_onSuccess_returnsResponse() async throws {
        let data = Data(#"{"templates":{}}"#.utf8)
        let response = HTTPURLResponse(
            url: URL(string: "https://consumer.inapp.customer.io/api/v1/templates")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        networkMock.requestClosure = { _, _, completionHandler in
            completionHandler(.success((data, response)))
        }

        let result = try await client.get(endpoint: .getTemplates, state: makeState())
        XCTAssertEqual(result.data, data)
        XCTAssertEqual(result.response.statusCode, 200)
    }

    // MARK: - Normal failure path (regression guard)

    func test_get_onTransportFailure_throwsInboxNetworkError() async {
        networkMock.requestClosure = { _, _, completionHandler in
            completionHandler(.failure(URLError(.notConnectedToInternet)))
        }

        do {
            _ = try await client.get(endpoint: .getTemplates, state: makeState())
            XCTFail("Expected an error to be thrown")
        } catch let error as InboxNetworkError {
            if case .transport = error { /* expected */ } else {
                XCTFail("Expected .transport, got \(error)")
            }
        } catch {
            XCTFail("Expected InboxNetworkError, got \(error)")
        }
    }

    func test_get_onMissingUserIdentifier_throwsMissingUserIdentifierError() async {
        networkMock.requestThrowableError = GistNetworkRequestError.missingUserIdentifier

        do {
            _ = try await client.get(endpoint: .getTemplates, state: makeState())
            XCTFail("Expected an error to be thrown")
        } catch let error as InboxNetworkError {
            XCTAssertEqual(error, .missingUserIdentifier)
        } catch {
            XCTFail("Expected InboxNetworkError.missingUserIdentifier, got \(error)")
        }
    }
}
