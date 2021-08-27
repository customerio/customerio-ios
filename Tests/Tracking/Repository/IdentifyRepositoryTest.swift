@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class IdentifyRepositoryTest: UnitTest {
    private var httpClientMock: HttpClientMock!
    private var keyValueStorageMock: KeyValueStorageMock!
    private var siteId: String!

    private var repository: IdentifyRepository!
    private var integrationRepository: IdentifyRepository!

    override func setUp() {
        super.setUp()

        httpClientMock = HttpClientMock()
        keyValueStorageMock = KeyValueStorageMock()
        siteId = String.random

        repository = CIOIdentifyRepository(httpClient: httpClientMock, keyValueStorage: keyValueStorageMock,
                                           siteId: siteId)
        integrationRepository = CIOIdentifyRepository(httpClient: httpClientMock, keyValueStorage: keyValueStorage,
                                                      siteId: siteId)
    }

    // MARK: addOrUpdateCustomer

    func test_addOrUpdateCustomer_expectCallHttpClientWithCorrectParams() {
        let givenIdentifier = String.random
        let givenEmail = EmailAddress.randomEmail
        let expectedBody = JsonAdapter.toJson(AddUpdateCustomerRequestBody(email: givenEmail, anonymousId: nil))!

        httpClientMock.requestClosure = { params, onComplete in
            guard case .identifyCustomer(let actualIdentifier) = params.endpoint else { return XCTFail() }
            XCTAssertEqual(actualIdentifier, givenIdentifier)

            XCTAssertEqual(params.body, expectedBody)

            onComplete(Result.success(expectedBody))
        }

        let expect = expectation(description: "Expect to complete")
        repository.addOrUpdateCustomer(identifier: givenIdentifier, email: givenEmail) { _ in
            expect.fulfill()
        }

        waitForExpectations()
    }

    func test_addOrUpdateCustomer_givenHttpFailure_expectDoNotSaveData_expectGetError() {
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.failure(HttpRequestError.unsuccessfulStatusCode(500, message: "")))
        }

        let expect = expectation(description: "Expect to complete")
        repository.addOrUpdateCustomer(identifier: String.random, email: nil) { result in
            guard case .failure(let actualError) = result else { return XCTFail() }
            guard case .httpError(let httpError) = actualError else { return XCTFail() }
            guard case .unsuccessfulStatusCode(let code, _) = httpError, code == 500 else { return XCTFail() }

            XCTAssertFalse(self.keyValueStorageMock.mockCalled)

            expect.fulfill()
        }

        waitForExpectations()
    }

    func test_addOrUpdateCustomer_givenHttpSuccess_expectSaveExpectedData() {
        let givenIdentifier = String.random
        let givenEmail = EmailAddress.randomEmail

        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }

        let expect = expectation(description: "Expect to complete")
        integrationRepository.addOrUpdateCustomer(identifier: givenIdentifier, email: givenEmail) { result in
            guard case .success = result else { return XCTFail() }

            XCTAssertEqual(self.keyValueStorage.string(siteId: self.siteId, forKey: .identifiedProfileId),
                           givenIdentifier)
            XCTAssertEqual(self.keyValueStorage.string(siteId: self.siteId, forKey: .identifiedProfileEmail),
                           givenEmail)

            expect.fulfill()
        }

        waitForExpectations()
    }

    // MARK: removeCustomer

    func test_removeCustomer_givenNeverIdentifiedProfile_expectIgnoreRequest() {
        integrationRepository.removeCustomer()

        XCTAssertNil(keyValueStorage.string(siteId: siteId, forKey: .identifiedProfileId))
        XCTAssertNil(keyValueStorage.string(siteId: siteId, forKey: .identifiedProfileEmail))
    }

    func test_removeCustomer_givenIdentifiedCustomer_expectCustomerRemoved() {
        let givenIdentifier = String.random
        let givenEmail = EmailAddress.randomEmail

        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }

        let expect = expectation(description: "Expect to complete")
        integrationRepository.addOrUpdateCustomer(identifier: givenIdentifier, email: givenEmail) { result in
            XCTAssertEqual(self.keyValueStorage.string(siteId: self.siteId, forKey: .identifiedProfileId),
                           givenIdentifier)
            XCTAssertEqual(self.keyValueStorage.string(siteId: self.siteId, forKey: .identifiedProfileEmail),
                           givenEmail)

            self.integrationRepository.removeCustomer()

            XCTAssertNil(self.keyValueStorage.string(siteId: self.siteId, forKey: .identifiedProfileId))
            XCTAssertNil(self.keyValueStorage.string(siteId: self.siteId, forKey: .identifiedProfileEmail))

            expect.fulfill()
        }

        waitForExpectations()
    }
}
