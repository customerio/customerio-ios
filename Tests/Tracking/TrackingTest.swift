@testable import Common
import Foundation
import SharedTests
@testable import Tracking
import XCTest

class TrackingTest: UnitTest {
    private var tracking: Tracking!

    private var identifyRepositoryMock: IdentifyRepositoryMock!

    override func setUp() {
        super.setUp()

        identifyRepositoryMock = IdentifyRepositoryMock()

        tracking = Tracking(customerIO: nil, identifyRepository: identifyRepositoryMock,
                            keyValueStorage: keyValueStorage)
    }

    // MARK: identify

    func test_identify_givenSdkNotInialized_expectFailureResult() {
        tracking = Tracking(customerIO: CustomerIO(), identifyRepository: nil, keyValueStorage: keyValueStorage)

        let expect = expectation(description: "Expect to complete identify")
        tracking.identify(identifier: String.random) { result in
            guard case .failure(let error) = result else { return XCTFail() }
            guard case .notInitialized = (error as! SdkError) else { return XCTFail() }

            XCTAssertFalse(self.identifyRepositoryMock.mockCalled)

            expect.fulfill()
        }

        waitForExpectations()
    }

    func test_identify_expectCallRepository() {
        let givenIdentifier = String.random
        let givenEmail = EmailAddress.randomEmail

        identifyRepositoryMock.addOrUpdateCustomerClosure = { actualIdentifier, actualEmail, onComplete in
            XCTAssertEqual(givenIdentifier, actualIdentifier)
            XCTAssertEqual(givenEmail, actualEmail)

            onComplete(Result.success(()))
        }

        let expect = expectation(description: "Expect to complete identify")
        tracking.identify(identifier: givenIdentifier, onComplete: { result in
            expect.fulfill()
        }, email: givenEmail)

        waitForExpectations()
    }

    func test_identify_givenFailedAddCustomer_expectFailureResult() {
        identifyRepositoryMock.addOrUpdateCustomerClosure = { _, _, onComplete in
            onComplete(Result.failure(HttpRequestError.unsuccessfulStatusCode(500)))
        }

        let expect = expectation(description: "Expect to complete identify")
        tracking.identify(identifier: String.random) { result in
            guard case .failure(let error) = result else { return XCTFail() }
            guard case .unsuccessfulStatusCode = (error as! HttpRequestError) else { return XCTFail() }

            expect.fulfill()
        }

        waitForExpectations()
    }

    func test_identify_givenSuccessfullyAddCustomer_expectSuccessResult() {
        identifyRepositoryMock.addOrUpdateCustomerClosure = { _, _, onComplete in
            onComplete(Result.success(()))
        }

        let expect = expectation(description: "Expect to complete identify")
        tracking.identify(identifier: String.random) { result in
            guard case .success = result else { return XCTFail() }

            expect.fulfill()
        }

        waitForExpectations()
    }
}
