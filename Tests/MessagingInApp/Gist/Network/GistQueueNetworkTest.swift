@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

class GistQueueNetworkTest: UnitTest {
    var network: GistQueueNetworkImpl!

    override func setUp() {
        super.setUp()
        network = GistQueueNetworkImpl()
    }

    // MARK: - User Identifier Validation

    // These success-path tests only verify the synchronous identifier-validation
    // branch of `request(...)`. The completion handler firing is incidental — the
    // assertion is "didn't throw." Waiting on a real `URLSession.shared` round-trip
    // (1s timeout) was the flake source; the network response is not part of the
    // contract these tests cover.

    func test_request_withUserId_expectSuccess() throws {
        let state = InAppMessageState(
            siteId: "test-site",
            dataCenter: "US",
            environment: .production,
            userId: "user123",
            anonymousId: nil
        )

        XCTAssertNoThrow(try network.request(state: state, request: QueueEndpoint.getUserQueue, completionHandler: { _ in }))
    }

    func test_request_withAnonymousId_expectSuccess() throws {
        let state = InAppMessageState(
            siteId: "test-site",
            dataCenter: "US",
            environment: .production,
            userId: nil,
            anonymousId: "anon123"
        )

        XCTAssertNoThrow(try network.request(state: state, request: QueueEndpoint.getUserQueue, completionHandler: { _ in }))
    }

    func test_request_withBothIdentifiers_expectSuccessWithUserId() throws {
        let state = InAppMessageState(
            siteId: "test-site",
            dataCenter: "US",
            environment: .production,
            userId: "user123",
            anonymousId: "anon123"
        )

        XCTAssertNoThrow(try network.request(state: state, request: QueueEndpoint.getUserQueue, completionHandler: { _ in }))
    }

    func test_request_withNoIdentifiers_expectThrowsMissingUserIdentifier() {
        let state = InAppMessageState(
            siteId: "test-site",
            dataCenter: "US",
            environment: .production,
            userId: nil,
            anonymousId: nil
        )

        // Should throw missingUserIdentifier error
        XCTAssertThrowsError(try network.request(state: state, request: QueueEndpoint.getUserQueue, completionHandler: { _ in })) { error in
            XCTAssertTrue(error is GistNetworkRequestError)
            if let networkError = error as? GistNetworkRequestError {
                XCTAssertEqual(networkError, .missingUserIdentifier)
            }
        }
    }

    func test_request_withBlankUserId_expectThrowsMissingUserIdentifier() {
        let state = InAppMessageState(
            siteId: "test-site",
            dataCenter: "US",
            environment: .production,
            userId: "   ",
            anonymousId: nil
        )

        // Should throw because userId is blank
        XCTAssertThrowsError(try network.request(state: state, request: QueueEndpoint.getUserQueue, completionHandler: { _ in })) { error in
            XCTAssertTrue(error is GistNetworkRequestError)
            if let networkError = error as? GistNetworkRequestError {
                XCTAssertEqual(networkError, .missingUserIdentifier)
            }
        }
    }

    func test_request_withBlankAnonymousId_expectThrowsMissingUserIdentifier() {
        let state = InAppMessageState(
            siteId: "test-site",
            dataCenter: "US",
            environment: .production,
            userId: nil,
            anonymousId: ""
        )

        // Should throw because anonymousId is empty
        XCTAssertThrowsError(try network.request(state: state, request: QueueEndpoint.getUserQueue, completionHandler: { _ in })) { error in
            XCTAssertTrue(error is GistNetworkRequestError)
            if let networkError = error as? GistNetworkRequestError {
                XCTAssertEqual(networkError, .missingUserIdentifier)
            }
        }
    }

    func test_request_withBlankUserIdAndValidAnonymousId_expectSuccess() throws {
        let state = InAppMessageState(
            siteId: "test-site",
            dataCenter: "US",
            environment: .production,
            userId: "  ",
            anonymousId: "anon123"
        )

        // Should not throw - falls back to anonymousId
        XCTAssertNoThrow(try network.request(state: state, request: QueueEndpoint.getUserQueue, completionHandler: { _ in }))
    }
}
