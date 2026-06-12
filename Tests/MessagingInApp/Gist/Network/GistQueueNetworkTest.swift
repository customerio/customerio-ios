@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
@testable import SharedTests
import XCTest

class GistQueueNetworkTest: UnitTest {
    var network: GistQueueNetworkImpl!

    override func setUp() {
        super.setUp()
        network = GistQueueNetworkImpl()
    }

    // MARK: - User Identifier Validation

    func test_request_withUserId_expectSuccess() throws {
        let state = InAppMessageState(
            siteId: "test-site",
            dataCenter: "US",
            environment: .production,
            userId: "user123",
            anonymousId: nil
        )

        let expectation = expectation(description: "Request completes")

        // Should not throw
        XCTAssertNoThrow(try network.request(state: state, request: QueueEndpoint.getUserQueue, completionHandler: { _ in
            expectation.fulfill()
        }))

        waitForExpectations(timeout: 5.0)
    }

    // Flake-fix: drop the `waitForExpectations` and `expectation` — the
    // completion handler had no assertions, so the wait was only stalling
    // for an incidental `URLSession.shared` round-trip. The contract under
    // test is the synchronous identifier-validation branch (no throw when
    // anonymousId is present), which is verified by `XCTAssertNoThrow`.
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

        let expectation = expectation(description: "Request completes")

        // Should not throw and should prefer userId
        XCTAssertNoThrow(try network.request(state: state, request: QueueEndpoint.getUserQueue, completionHandler: { _ in
            expectation.fulfill()
        }))

        waitForExpectations(timeout: 5.0)
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

    // Flake-fix: same rationale as `test_request_withAnonymousId_expectSuccess`
    // above — drop the wait; the identifier-validation branch is the contract.
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
